cmake_minimum_required(VERSION 3.5.0)
project(proton_hsp)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH})

set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/native-out)

add_library(proton SHARED napi_init.cpp)
target_link_libraries(proton PUBLIC
    libace_ndk.z.so
    libace_napi.z.so
    libhilog_ndk.z.so
    libdl.so
    libvulkan.so
    libnative_buffer.so
    libnative_window.so
)

add_library(proton_hmos_runtime SHARED runtime_bridge.cpp)
target_link_libraries(proton_hmos_runtime PUBLIC
    libhilog_ndk.z.so
    libdl.so
)

get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
set(WINE_SOURCE_ROOT "${PROJECT_ROOT}/third_party/proton-runtime/src/proton/wine")
set(WINE_HMOS_CONFIG_ROOT "${PROJECT_ROOT}/third_party/proton-runtime/hmos/wine-server")
file(GLOB WINE_SERVER_SOURCES "${WINE_SOURCE_ROOT}/server/*.c")
if(WINE_SERVER_SOURCES AND EXISTS "${WINE_SOURCE_ROOT}/include")
    set_source_files_properties(${WINE_SERVER_SOURCES} PROPERTIES
        COMPILE_DEFINITIONS "main=wine_hmos_wineserver_main;exit=wine_hmos_server_exit;__WINESRC__;_GNU_SOURCE;__ANDROID__;WINE_HMOS_NATIVE_SERVER"
        COMPILE_OPTIONS "-include;stdarg.h"
    )
    add_library(wine_hmos_server SHARED wine_server_bridge.cpp ${WINE_SERVER_SOURCES})
    target_compile_definitions(wine_hmos_server PRIVATE WINE_HMOS_HAS_NATIVE_SERVER=1)
    target_include_directories(wine_hmos_server PRIVATE
        ${WINE_HMOS_CONFIG_ROOT}
        ${WINE_SOURCE_ROOT}/include
        ${WINE_SOURCE_ROOT}/server
    )
else()
    message(WARNING "Wine server sources missing under ${WINE_SOURCE_ROOT}; building stub wine_hmos_server")
    add_library(wine_hmos_server SHARED wine_server_bridge.cpp)
    target_compile_definitions(wine_hmos_server PRIVATE WINE_HMOS_SERVER_STUB=1)
endif()
target_link_libraries(wine_hmos_server PUBLIC
    libhilog_ndk.z.so
    libdl.so
)

add_library(box64_hmos SHARED box64_adapter.cpp)
target_link_libraries(box64_hmos PUBLIC
    libhilog_ndk.z.so
    libdl.so
)

set(BOX64_HMOS_CORE_PREBUILT "${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a/libbox64_hmos_core.so")
set(BOX64_HMOS_CORE_OUTPUT "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libbox64_hmos_core.so")
if(EXISTS "${BOX64_HMOS_CORE_PREBUILT}")
    add_library(box64_hmos_core SHARED IMPORTED GLOBAL)
    set_target_properties(box64_hmos_core PROPERTIES
        IMPORTED_LOCATION "${BOX64_HMOS_CORE_PREBUILT}"
    )
    add_custom_command(
        OUTPUT "${BOX64_HMOS_CORE_OUTPUT}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${BOX64_HMOS_CORE_PREBUILT}" "${BOX64_HMOS_CORE_OUTPUT}"
        DEPENDS "${BOX64_HMOS_CORE_PREBUILT}"
        COMMENT "Copying Box64 HMOS in-process core"
        VERBATIM
    )
    add_custom_target(box64_hmos_core_payload ALL DEPENDS "${BOX64_HMOS_CORE_OUTPUT}")
    add_dependencies(proton box64_hmos_core_payload)
    add_dependencies(box64_hmos box64_hmos_core_payload)
    target_link_libraries(proton PUBLIC box64_hmos_core)
    target_link_libraries(box64_hmos PUBLIC box64_hmos_core)
else()
    message(WARNING "Box64 HMOS core prebuilt missing: ${BOX64_HMOS_CORE_PREBUILT}")
endif()
