#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <memory>
#include <mutex>
#include <string>

namespace Ort {
struct Env;
struct Session;
}

namespace godot {

class CrepePitchExtractor : public RefCounted {
	GDCLASS(CrepePitchExtractor, RefCounted)

public:
	CrepePitchExtractor();
	~CrepePitchExtractor() override;

	bool initialize_model(const PackedByteArray &model_bytes);
	bool is_ready() const;
	String get_last_error() const;
	Dictionary extract_pitch(const PackedFloat32Array &samples, int sample_rate);

protected:
	static void _bind_methods();

private:
	void set_error(const std::string &message);

	std::unique_ptr<Ort::Env> environment;
	std::unique_ptr<Ort::Session> session;
	PackedByteArray owned_model_bytes;
	std::string input_name;
	std::string output_name;
	mutable std::mutex state_mutex;
	std::string last_error;
};

} // namespace godot
