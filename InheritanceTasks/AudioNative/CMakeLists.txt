cmake_minimum_required(VERSION 3.20)
project(chuwuzhi_audio LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED GODOT_CPP_DIR)
	message(FATAL_ERROR "Set GODOT_CPP_DIR to a godot-cpp checkout compatible with Godot 4.5+.")
endif()
if(NOT DEFINED ONNXRUNTIME_ROOT)
	message(FATAL_ERROR "Set ONNXRUNTIME_ROOT to the extracted Microsoft.ML.OnnxRuntime package.")
endif()

add_subdirectory("${GODOT_CPP_DIR}" godot-cpp EXCLUDE_FROM_ALL)

add_library(chuwuzhi_audio SHARED
	src/crepe_pitch_extractor.cpp
	src/register_types.cpp
)

target_include_directories(chuwuzhi_audio PRIVATE
	"${ONNXRUNTIME_ROOT}/build/native/include"
)

target_link_libraries(chuwuzhi_audio PRIVATE
	godot::cpp
	"${ONNXRUNTIME_ROOT}/runtimes/win-x64/native/onnxruntime.lib"
)

if(MSVC)
	target_compile_options(chuwuzhi_audio PRIVATE /utf-8 /W4 /permissive-)
	set_property(TARGET chuwuzhi_audio PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

set_target_properties(chuwuzhi_audio PROPERTIES
	PREFIX ""
	OUTPUT_NAME "chuwuzhi_audio.windows.x86_64"
	RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
	RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/bin"
	RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/bin"
)
