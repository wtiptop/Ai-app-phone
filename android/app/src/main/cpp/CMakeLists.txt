cmake_minimum_required(VERSION 3.22)
project(scalajaca_local LANGUAGES C CXX)
if(ANDROID)
    # AGP uruchomiony bezpośrednio może nadpisać argument build.gradle na
    # małe "debug" bez optymalizacji. LLM wymaga zoptymalizowanego CPU także
    # w instalacyjnym APK debug. Ta polityka obejmuje oba silniki i ggml.
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Native inference optimization" FORCE)
    set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG" CACHE STRING "" FORCE)
    set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG" CACHE STRING "" FORCE)
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
get_filename_component(LLAMA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/llama.cpp" ABSOLUTE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_UI OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)
set(LLAMA_LLGUIDANCE OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
if(ANDROID AND ANDROID_ABI STREQUAL "x86_64")
    # Bazowy zestaw instrukcji ABI Android x86_64, także dla emulatora bez AVX.
    set(GGML_SSE42 ON CACHE BOOL "" FORCE)
    foreach(feature AVX AVX2 AVX_VNNI AVX512 AVX512_VBMI AVX512_VNNI AVX512_BF16 FMA F16C BMI2)
        set(GGML_${feature} OFF CACHE BOOL "" FORCE)
    endforeach()
endif()
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_BLAS OFF CACHE BOOL "" FORCE)
set(FETCHCONTENT_FULLY_DISCONNECTED ON CACHE BOOL "" FORCE)
add_subdirectory("${LLAMA_ROOT}" llama-build EXCLUDE_FROM_ALL)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/templates/MiniCPM5-1B.jinja" TEMPLATE_1B)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/templates/MiniCPM5-2B.jinja" TEMPLATE_2B)
configure_file(templates.h.in "${CMAKE_CURRENT_BINARY_DIR}/templates.h" @ONLY)
add_library(scalajaca_core STATIC
    local_engine.cpp
    "${LLAMA_ROOT}/common/json.cpp"
    "${LLAMA_ROOT}/common/unicode.cpp"
    "${LLAMA_ROOT}/common/jinja/lexer.cpp"
    "${LLAMA_ROOT}/common/jinja/parser.cpp"
    "${LLAMA_ROOT}/common/jinja/runtime.cpp"
    "${LLAMA_ROOT}/common/jinja/value.cpp"
    "${LLAMA_ROOT}/common/jinja/string.cpp")
target_include_directories(scalajaca_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}" PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}" "${LLAMA_ROOT}/common" "${LLAMA_ROOT}/vendor")
target_link_libraries(scalajaca_core PUBLIC llama)
if(MSVC)
    target_compile_options(scalajaca_core PRIVATE /utf-8)
endif()
if(ANDROID)
    get_filename_component(COLIBRI_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/colibri" ABSOLUTE)
    include("${COLIBRI_ROOT}/../../tools/colibri/patch_olmoe.cmake")
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${COLIBRI_ROOT}/c/olmoe.c")
    set(COLIBRI_PATCHED_DIR "${CMAKE_CURRENT_BINARY_DIR}/colibri_patched")
    scalajaca_patch_olmoe("${COLIBRI_ROOT}/c/olmoe.c" "${COLIBRI_PATCHED_DIR}/scalajaca_olmoe.c")
    add_library(scalajaca_colibri SHARED colibri_bridge.c)
    target_include_directories(scalajaca_colibri PRIVATE "${COLIBRI_PATCHED_DIR}" "${COLIBRI_ROOT}/c")
    # Statyczny runtime NDK: brak zależności od libomp.so na telefonie.
    # Aktywuje oryginalne pragmy upstream, także SIMD reduction (możliwe
    # różnice zaokrągleń względem dawnego builda bez OpenMP). IDOT pozostaje 0.
    target_compile_options(scalajaca_colibri PRIVATE -O3 -fopenmp)
    target_link_options(scalajaca_colibri PRIVATE -fopenmp -static-openmp)
    if(ANDROID_ABI STREQUAL "x86_64")
        target_compile_options(scalajaca_colibri PRIVATE -msse4.2)
    endif()
    target_link_libraries(scalajaca_colibri PRIVATE m)
    target_link_options(scalajaca_colibri PRIVATE "-Wl,-z,max-page-size=16384")
    add_library(scalajaca_llama SHARED jni_bridge.cpp)
    target_link_libraries(scalajaca_llama PRIVATE scalajaca_core)
    target_link_options(scalajaca_llama PRIVATE "-Wl,-z,max-page-size=16384")
else()
    add_executable(scalajaca_local_smoke local_smoke.cpp)
    target_link_libraries(scalajaca_local_smoke PRIVATE scalajaca_core)
    if(MSVC)
        target_compile_options(scalajaca_local_smoke PRIVATE /utf-8)
    endif()
endif()
