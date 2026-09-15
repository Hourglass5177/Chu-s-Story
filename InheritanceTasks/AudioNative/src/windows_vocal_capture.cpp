#include "windows_vocal_capture.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <wrl/client.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>

using namespace godot;
using Microsoft::WRL::ComPtr;
namespace {
constexpr int RATE = 16000;
struct ComScope {
    HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    ~ComScope() { if (SUCCEEDED(result)) CoUninitialize(); }
};
struct MixFormat {
    WAVEFORMATEX *value = nullptr;
    ~MixFormat() { CoTaskMemFree(value); }
};
}

void WindowsVocalCapture::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "duration", "probe_only"), &WindowsVocalCapture::start, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("get_status"), &WindowsVocalCapture::get_status);
    ClassDB::bind_method(D_METHOD("take_result"), &WindowsVocalCapture::take_result);
    ClassDB::bind_method(D_METHOD("set_paused", "paused"), &WindowsVocalCapture::set_paused);
    ClassDB::bind_method(D_METHOD("cancel"), &WindowsVocalCapture::cancel);
}

WindowsVocalCapture::~WindowsVocalCapture() { cancel(); }
bool WindowsVocalCapture::start(double duration, bool probe_only) {
    if (worker.joinable() || !std::isfinite(duration) || duration <= 0 || duration > 60) return false;
    stopping = false;
    paused = false;
    { std::lock_guard<std::mutex> lock(mutex);
      samples.clear(); error.clear(); ready = done = false; level = 0;
      device_channels = device_rate = 0;
    }
    try { worker = std::thread(&WindowsVocalCapture::run, this, duration, probe_only); }
    catch (...) { fail("thread_start", E_FAIL); return false; }
    return true;
}
void WindowsVocalCapture::set_paused(bool value) { paused = value; }
void WindowsVocalCapture::cancel() {
    stopping = true;
    if (worker.joinable()) worker.join();
    std::lock_guard<std::mutex> lock(mutex);
    std::fill(samples.begin(), samples.end(), 0.0f);
    samples.clear(); level = 0;
}
void WindowsVocalCapture::fail(const char *stage, long code) {
    char text[128];
    snprintf(text, sizeof(text), "%s:0x%08lX", stage, static_cast<unsigned long>(code));
    std::lock_guard<std::mutex> lock(mutex);
    error = text; done = true;
}
Dictionary WindowsVocalCapture::get_status() const {
    std::lock_guard<std::mutex> lock(mutex);
    Dictionary status;
    status["ready"] = ready; status["done"] = done;
    status["error"] = String(error.c_str());
    status["seconds"] = double(samples.size()) / RATE;
    status["level"] = paused ? 0.0 : double(level);
    status["device_channels"] = device_channels;
    status["device_rate"] = device_rate;
    return status;
}
Dictionary WindowsVocalCapture::take_result() {
    // Never wait for a live capture/driver on the UI thread.
    { std::lock_guard<std::mutex> lock(mutex);
      if (!done) { Dictionary result; result["ok"] = false; result["error"] = "capture_not_finished"; return result; }
    }
    if (worker.joinable()) worker.join();
    std::lock_guard<std::mutex> lock(mutex);
    Dictionary result;
    PackedFloat32Array audio;
    if (error.empty() && !samples.empty()) {
        audio.resize(samples.size());
        std::copy(samples.begin(), samples.end(), audio.ptrw());
    }
    result["ok"] = error.empty() && !samples.empty();
    result["error"] = String(error.c_str());
    result["samples"] = audio; result["sample_rate"] = RATE;
    std::fill(samples.begin(), samples.end(), 0.0f);
    samples.clear();
    return result;
}
void WindowsVocalCapture::run(double duration, bool probe_only) {
    ComScope com;
    if (FAILED(com.result)) { fail("com_init", com.result); return; }
    ComPtr<IMMDeviceEnumerator> enumerator;
    ComPtr<IMMDevice> device;
    ComPtr<IAudioClient> client;
    ComPtr<IAudioCaptureClient> capture;
    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
    if (FAILED(hr)) { fail("device_enumerator", hr); return; }
    hr = enumerator->GetDefaultAudioEndpoint(eCapture, eMultimedia, &device);
    if (FAILED(hr)) { fail("default_microphone", hr); return; }
    hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void **>(client.GetAddressOf()));
    if (FAILED(hr)) { fail("microphone_activate", hr); return; }
    MixFormat mix;
    hr = client->GetMixFormat(&mix.value);
    if (FAILED(hr)) { fail("microphone_format", hr); return; }
    { std::lock_guard<std::mutex> lock(mutex);
      device_channels = mix.value->nChannels; device_rate = mix.value->nSamplesPerSec;
    }
    // Let the Windows audio engine convert ALL endpoint channel layouts to the
    // exact mono float format CREPE consumes; never change system device settings.
    WAVEFORMATEX format{};
    format.wFormatTag = WAVE_FORMAT_IEEE_FLOAT;
    format.nChannels = 1; format.nSamplesPerSec = RATE;
    format.wBitsPerSample = 32; format.nBlockAlign = 4;
    format.nAvgBytesPerSec = RATE * 4;
    hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        1000000, 0, &format, nullptr);
    if (FAILED(hr)) { fail("microphone_conversion", hr); return; }
    hr = client->GetService(IID_PPV_ARGS(&capture));
    if (FAILED(hr)) { fail("capture_service", hr); return; }
    if (probe_only) {
        std::lock_guard<std::mutex> lock(mutex); ready = done = true; return;
    }
    if (stopping) return;
    hr = client->Start();
    if (FAILED(hr)) { fail("capture_start", hr); return; }
    { std::lock_guard<std::mutex> lock(mutex); ready = true; samples.reserve(size_t(duration * RATE)); }
    const size_t limit = size_t(std::ceil(duration * RATE));
    size_t count = 0;
    bool first_packet = true, was_paused = false;
    auto last_packet = std::chrono::steady_clock::now();
    while (!stopping && count < limit) {
        UINT32 packet = 0;
        hr = capture->GetNextPacketSize(&packet);
        if (FAILED(hr)) { fail("capture_device_lost", hr); break; }
        bool skip = paused.load();
        // Drain and discard buffered audio at pause/resume boundaries too.
        bool transition = skip != was_paused;
        was_paused = skip;
        while (packet && !stopping) {
            BYTE *data = nullptr; UINT32 frames = 0; DWORD flags = 0;
            hr = capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
            if (FAILED(hr)) { fail("capture_read", hr); break; }
            bool glitch = !first_packet && !skip && !transition &&
                (flags & (AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY | AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR));
            first_packet = false;
            if (!skip && !transition && !glitch) {
                std::lock_guard<std::mutex> lock(mutex);
                const float *values = reinterpret_cast<const float *>(data);
                double power = 0;
                for (UINT32 i = 0; i < frames && count < limit; ++i) {
                    float value = (flags & AUDCLNT_BUFFERFLAGS_SILENT) ? 0.0f : values[i];
                    if (!std::isfinite(value)) value = 0;
                    samples.push_back(value); power += double(value) * value; ++count;
                }
                level = float(std::sqrt(power / std::max<UINT32>(frames, 1)));
            }
            hr = capture->ReleaseBuffer(frames);
            last_packet = std::chrono::steady_clock::now();
            if (glitch) { fail("capture_discontinuity", E_FAIL); hr = E_FAIL; break; }
            if (FAILED(hr)) { fail("capture_release", hr); break; }
            hr = capture->GetNextPacketSize(&packet);
            if (FAILED(hr)) { fail("capture_device_lost", hr); break; }
        }
        if (FAILED(hr)) break;
        if (std::chrono::steady_clock::now() - last_packet > std::chrono::seconds(3)) {
            fail("capture_stalled", E_FAIL); break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    client->Stop();
    std::lock_guard<std::mutex> lock(mutex);
    done = true;
}
