#include "crepe_pitch_extractor.h"

#include <godot_cpp/core/class_db.hpp>

#include <onnxruntime_cxx_api.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace {

constexpr int kModelSampleRate = 16000;
constexpr int kFrameLength = 1024;
constexpr int kHopLength = 160;
constexpr int kOutputBins = 360;
constexpr int kInferenceBatchSize = 128;
constexpr double kModelBaseCents = 1997.3794084376191;
constexpr double kModelRangeCents = 7180.0;
constexpr double kBaseFrequency = 10.0;

std::vector<float> resample_linear(
		const godot::PackedFloat32Array &source,
		const int source_rate) {
	if (source_rate == kModelSampleRate) {
		std::vector<float> result(static_cast<size_t>(source.size()));
		for (int index = 0; index < source.size(); ++index) {
			result[static_cast<size_t>(index)] = source[index];
		}
		return result;
	}

	const double ratio = static_cast<double>(kModelSampleRate) /
			static_cast<double>(source_rate);
	const size_t target_size = std::max<size_t>(
			1,
			static_cast<size_t>(std::floor(static_cast<double>(source.size()) * ratio)));
	std::vector<float> result(target_size);
	for (size_t target_index = 0; target_index < target_size; ++target_index) {
		const double source_position = static_cast<double>(target_index) / ratio;
		const size_t left = std::min<size_t>(
				static_cast<size_t>(source_position),
				static_cast<size_t>(source.size() - 1));
		const size_t right = std::min<size_t>(left + 1, static_cast<size_t>(source.size() - 1));
		const double fraction = source_position - static_cast<double>(left);
		result[target_index] = static_cast<float>(
				static_cast<double>(source[static_cast<int>(left)]) * (1.0 - fraction) +
				static_cast<double>(source[static_cast<int>(right)]) * fraction);
	}
	return result;
}

void normalize_frame(std::vector<float> &frame) {
	const double mean = std::accumulate(frame.begin(), frame.end(), 0.0) /
			static_cast<double>(frame.size());
	double square_sum = 0.0;
	for (float &sample : frame) {
		sample = static_cast<float>(static_cast<double>(sample) - mean);
		square_sum += static_cast<double>(sample) * static_cast<double>(sample);
	}
	const double deviation = std::sqrt(square_sum / static_cast<double>(frame.size()));
	if (deviation <= 1.0e-10) {
		return;
	}
	for (float &sample : frame) {
		sample = static_cast<float>(static_cast<double>(sample) / deviation);
	}
}

float pitch_from_bin(const int bin) {
	const double cents = kModelBaseCents +
			static_cast<double>(bin) * (kModelRangeCents / static_cast<double>(kOutputBins - 1));
	return static_cast<float>(kBaseFrequency * std::pow(2.0, cents / 1200.0));
}

} // namespace

namespace godot {

CrepePitchExtractor::CrepePitchExtractor() = default;
CrepePitchExtractor::~CrepePitchExtractor() = default;

void CrepePitchExtractor::_bind_methods() {
	ClassDB::bind_method(
			D_METHOD("initialize_model", "model_bytes"),
			&CrepePitchExtractor::initialize_model);
	ClassDB::bind_method(D_METHOD("is_ready"), &CrepePitchExtractor::is_ready);
	ClassDB::bind_method(D_METHOD("get_last_error"), &CrepePitchExtractor::get_last_error);
	ClassDB::bind_method(
			D_METHOD("extract_pitch", "samples", "sample_rate"),
			&CrepePitchExtractor::extract_pitch);
}

void CrepePitchExtractor::set_error(const std::string &message) {
	last_error = message;
}

bool CrepePitchExtractor::initialize_model(const PackedByteArray &model_bytes) {
	std::lock_guard<std::mutex> guard(state_mutex);
	session.reset();
	environment.reset();
	input_name.clear();
	output_name.clear();
	owned_model_bytes = PackedByteArray();
	set_error("");

	if (model_bytes.is_empty()) {
		set_error("CREPE model data is empty.");
		return false;
	}

	try {
		owned_model_bytes = model_bytes;
		environment = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "ChuwuzhiCrepe");
		Ort::SessionOptions options;
		options.SetIntraOpNumThreads(1);
		options.SetInterOpNumThreads(1);
		options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
		session = std::make_unique<Ort::Session>(
				*environment,
				owned_model_bytes.ptr(),
				static_cast<size_t>(owned_model_bytes.size()),
				options);
		Ort::AllocatorWithDefaultOptions allocator;
		auto input = session->GetInputNameAllocated(0, allocator);
		auto output = session->GetOutputNameAllocated(0, allocator);
		input_name = input.get();
		output_name = output.get();
		return true;
	} catch (const Ort::Exception &error) {
		set_error(error.what());
		session.reset();
		environment.reset();
		owned_model_bytes = PackedByteArray();
		return false;
	}
}

bool CrepePitchExtractor::is_ready() const {
	std::lock_guard<std::mutex> guard(state_mutex);
	return session != nullptr;
}

String CrepePitchExtractor::get_last_error() const {
	std::lock_guard<std::mutex> guard(state_mutex);
	return String(last_error.c_str());
}

Dictionary CrepePitchExtractor::extract_pitch(
		const PackedFloat32Array &samples,
		const int sample_rate) {
	std::lock_guard<std::mutex> guard(state_mutex);
	Dictionary result;
	result["ok"] = false;
	result["error"] = String();

	if (session == nullptr) {
		set_error("CREPE model has not been initialized.");
		result["error"] = String(last_error.c_str());
		return result;
	}
	if (sample_rate <= 0 || samples.size() < 2) {
		set_error("Recorded audio is empty or has an invalid sample rate.");
		result["error"] = String(last_error.c_str());
		return result;
	}

	try {
		const std::vector<float> resampled = resample_linear(samples, sample_rate);
		if (resampled.size() < static_cast<size_t>(kFrameLength)) {
			set_error("Recorded audio is too short for pitch analysis.");
			result["error"] = String(last_error.c_str());
			return result;
		}

		const int frame_count = static_cast<int>(
				(resampled.size() - static_cast<size_t>(kFrameLength)) /
				static_cast<size_t>(kHopLength) + 1);
		PackedFloat32Array times;
		PackedFloat32Array pitches;
		PackedFloat32Array confidences;
		times.resize(frame_count);
		pitches.resize(frame_count);
		confidences.resize(frame_count);

		Ort::MemoryInfo memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
		const char *input_names[] = {input_name.c_str()};
		const char *output_names[] = {output_name.c_str()};
		for (int batch_start = 0; batch_start < frame_count; batch_start += kInferenceBatchSize) {
			const int batch_count = std::min(kInferenceBatchSize, frame_count - batch_start);
			std::vector<float> batch(
					static_cast<size_t>(batch_count) * static_cast<size_t>(kFrameLength));
			std::vector<float> frame(static_cast<size_t>(kFrameLength));
			for (int batch_index = 0; batch_index < batch_count; ++batch_index) {
				const int frame_index = batch_start + batch_index;
				const size_t offset = static_cast<size_t>(frame_index * kHopLength);
				std::copy_n(resampled.data() + offset, kFrameLength, frame.data());
				normalize_frame(frame);
				std::copy(
						frame.begin(),
						frame.end(),
						batch.begin() + static_cast<size_t>(batch_index * kFrameLength));
			}
			const std::array<int64_t, 2> input_shape = {batch_count, kFrameLength};
			Ort::Value tensor = Ort::Value::CreateTensor<float>(
					memory,
					batch.data(),
					batch.size(),
					input_shape.data(),
					input_shape.size());
			auto outputs = session->Run(
					Ort::RunOptions{nullptr},
					input_names,
					&tensor,
					1,
					output_names,
					1);
			const float *activations = outputs.front().GetTensorData<float>();
			const size_t output_count = outputs.front().GetTensorTypeAndShapeInfo().GetElementCount();
			if (output_count < static_cast<size_t>(batch_count * kOutputBins)) {
				throw std::runtime_error("CREPE output does not contain 360 pitch bins.");
			}
			for (int batch_index = 0; batch_index < batch_count; ++batch_index) {
				const int frame_index = batch_start + batch_index;
				const size_t offset = static_cast<size_t>(frame_index * kHopLength);
				const float *activation = activations + static_cast<size_t>(batch_index * kOutputBins);
				int best_bin = 0;
				float confidence = activation[0];
				for (int bin = 1; bin < kOutputBins; ++bin) {
					if (activation[bin] > confidence) {
						confidence = activation[bin];
						best_bin = bin;
					}
				}
				times[frame_index] = static_cast<float>(offset) / static_cast<float>(kModelSampleRate);
				pitches[frame_index] = pitch_from_bin(best_bin);
				confidences[frame_index] = confidence;
			}
		}

		set_error("");
		result["ok"] = true;
		result["times"] = times;
		result["pitches"] = pitches;
		result["confidences"] = confidences;
		result["sample_rate"] = kModelSampleRate;
		return result;
	} catch (const Ort::Exception &error) {
		set_error(error.what());
	} catch (const std::exception &error) {
		set_error(error.what());
	}

	result["error"] = String(last_error.c_str());
	return result;
}

} // namespace godot
