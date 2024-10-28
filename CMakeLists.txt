cmake_minimum_required(VERSION 3.19)

function(generate_compile_flags TARGET_NAME DST_DIR)
    message(STATUS "Generate compile_flags.txt: ${DST_DIR}")
    set(COMPILE_FLAGS "")
    get_target_property(include_dirs ${TARGET_NAME} INCLUDE_DIRECTORIES)
    foreach(dir IN LISTS include_dirs)
        string(APPEND COMPILE_FLAGS "-I${dir}\n")
    endforeach()
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/compile_flags.txt.in" "${DST_DIR}/compile_flags.txt" @ONLY)
endfunction()

project(sokol-app CXX)
set(CMAKE_CXX_STANDARD 20)

file(GLOB_RECURSE SOURCES "src/*.m" "src/*.mm" "src/*.c" "src/*.cc")

add_subdirectory(packages)

if (APPLE)
    set(CMAKE_CONFIGURATION_TYPES "Debug;Release")
    set(CMAKE_XCODE_GENERATE_SCHEME TRUE)
    set(CMAKE_OSX_ARCHITECTURES "arm64")

    add_executable(cocoa MACOSX_BUNDLE ${SOURCES})
    target_compile_options(cocoa PRIVATE -fobjc-arc)
    target_include_directories(cocoa PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/packages/sokol
        ${CMAKE_CURRENT_SOURCE_DIR}/packages/sokol/util
        ${CMAKE_CURRENT_SOURCE_DIR}/packages/imgui
    )
    target_link_libraries(cocoa imgui)
    target_link_libraries(cocoa
        "-framework Cocoa"
        "-framework Metal"
        "-framework MetalKit"
        "-framework Quartz"
    )
    generate_compile_flags(cocoa ${CMAKE_CURRENT_SOURCE_DIR})
endif (APPLE)




