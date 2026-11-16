# llama.cpp from a pinned release, checked by hash. It is downloaded at build time only: the app never fetches code.
# Its own ggml is linked in statically and hidden, so whisper's ggml, in the other library, cannot clash with it.
cmake_minimum_required(VERSION 3.22)
project(meetlaud_llama C CXX)

include(FetchContent)
FetchContent_Declare(llama
    URL https://github.com/ggml-org/llama.cpp/archive/refs/tags/b12405.tar.gz
    URL_HASH SHA256=d100283a39c85635f852085843870b8eae378c3a4626c72755b3c574e3c4819c)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
# ggml's own thread pool: OpenMP would need libomp.so, which Android does not ship.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
# KleidiAI would download more code during the build. The plain ARM kernels are close enough on a phone.
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
# Plain ARMv8: phones still sold with Cortex-A73 and A53 cores (Snapdragon 680) have no dot product or fp16
# instructions, and would crash on them.
set(GGML_CPU_ARM_ARCH "armv8-a" CACHE STRING "" FORCE)
# No network inside the library, ever: model files arrive only through ModelDelivery.
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(llama)

add_library(meetlaud_llama SHARED llama_jni.cpp)
target_link_libraries(meetlaud_llama PRIVATE llama log)
target_compile_options(meetlaud_llama PRIVATE -O3 -fvisibility=hidden -fvisibility-inlines-hidden)
target_link_options(meetlaud_llama PRIVATE -Wl,--exclude-libs,ALL -Wl,--gc-sections -Wl,-z,max-page-size=16384)
