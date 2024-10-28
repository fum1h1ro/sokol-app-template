cmake_minimum_required(VERSION 3.19)
set(CMAKE_CXX_STANDARD 20)

project(imgui_lib CXX)

file(GLOB SOURCES "imgui/*.cpp")
list(APPEND SOURCES "imgui/backends/imgui_impl_metal.mm")
add_library(imgui STATIC ${SOURCES})
target_include_directories(imgui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/imgui)
