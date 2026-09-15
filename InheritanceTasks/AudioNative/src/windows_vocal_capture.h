#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <atomic>
#include <mutex>
#include <thread>
#include <vector>
#include <string>

namespace godot {
// Owns only a bounded, in-memory microphone recording. No Godot audio driver,
// scene nodes, model inference, filesystem or network access on this thread.
class WindowsVocalCapture : public RefCounted {
    GDCLASS(WindowsVocalCapture, RefCounted)
    std::thread worker;
    std::atomic<bool> stopping{false}, paused{false};
    mutable std::mutex mutex;
    std::vector<float> samples;
    bool ready = false, done = false;
    int device_channels = 0, device_rate = 0;
    std::string error;
    float level = 0;
    void run(double duration, bool probe_only);
    void fail(const char *stage, long code);
protected:
    static void _bind_methods();
public:
    ~WindowsVocalCapture() override;
    bool start(double duration, bool probe_only = false);
    void set_paused(bool value);
    void cancel();
    Dictionary get_status() const;
    Dictionary take_result();
};
}
