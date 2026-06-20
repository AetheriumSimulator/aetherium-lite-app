cmake_minimum_required(VERSION 3.5.0)
project(proton_hmos_entry)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/native-out)

add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
)
