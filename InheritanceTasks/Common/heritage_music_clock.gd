class_name HeritageMusicClock
extends AudioStreamPlayer

var output_latency: float = 0.0
var last_time: float = 0.0
var started: bool = false
var _output_device: String = ""

func begin(audio: AudioStream) -> void:
	stream = audio
	output_latency = AudioServer.get_output_latency()
	_output_device = AudioServer.output_device
	last_time = 0.0
	started = true
	play()

func seconds() -> float:
	if not started or stream_paused: return last_time
	if _output_device != AudioServer.output_device:
		_output_device = AudioServer.output_device
		output_latency = AudioServer.get_output_latency()
	var sampled: float = get_playback_position() + AudioServer.get_time_since_last_mix() - output_latency
	last_time = maxf(last_time, sampled)
	return last_time

func freeze(value: bool) -> void:
	if value: seconds()
	stream_paused = value
