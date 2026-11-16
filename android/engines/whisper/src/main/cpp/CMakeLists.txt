# whisper.cpp from a pinned release, checked by hash. It is downloaded at build time only: the app never fetches code.
# Its own ggml is linked in statically and hidden, so llama's ggml, in the other library, cannot clash with it.
cmake_minimum_required(VERSION 3.22)
project(meetlaud_whisper C CXX)

include(FetchContent)
FetchContent_Declare(whisper
    URL https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz
    URL_HASH SHA256=ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# ggml's own thread pool: OpenMP would need libomp.so, which Android does not ship.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
# Plain ARMv8: phones still sold with Cortex-A73 and A53 cores (Snapdragon 680) have no dot product or fp16
# instructions, and would crash on them.
set(GGML_CPU_ARM_ARCH "armv8-a" CACHE STRING "" FORCE)
# No network inside the library, ever: model files arrive only through ModelDelivery.
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(whisper)

add_library(meetlaud_whisper SHARED whisper_jni.cpp)
target_link_libraries(meetlaud_whisper PRIVATE whisper log)
target_compile_options(meetlaud_whisper PRIVATE -O3 -fvisibility=hidden -fvisibility-inlines-hidden)
target_link_options(meetlaud_whisper PRIVATE -Wl,--exclude-libs,ALL -Wl,--gc-sections -Wl,-z,max-page-size=16384)
