
cmake_minimum_required(VERSION 3.20)

project(
  emacs-frame-overlay
  VERSION 0.1.0
  LANGUAGES CXX
)

if(NOT WIN32)
  message(FATAL_ERROR
    "emacs-frame-overlay currently supports Windows only.")
endif()

# output directory
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# output compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(
  FRAME_OVERLAY_BUILD_TESTS
  "Build frame-overlay tests"
  OFF
)

add_subdirectory(main)

if(FRAME_OVERLAY_BUILD_TESTS)
  enable_testing()
  add_subdirectory(test)
endif()

