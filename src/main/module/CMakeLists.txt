
set(FRAME_OVERLAY_MODULE_TARGET frame-overlay-module)

add_library(
  ${FRAME_OVERLAY_MODULE_TARGET}
  MODULE
  frame_overlay_module.cpp
)

target_compile_features(
  ${FRAME_OVERLAY_MODULE_TARGET}
  PRIVATE
  cxx_std_20
)

target_include_directories(
  ${FRAME_OVERLAY_MODULE_TARGET}
  PRIVATE
  "${EMACS_INCLUDE_DIR}"
)

target_link_libraries(
  ${FRAME_OVERLAY_MODULE_TARGET}
  PRIVATE
  gdi32
  user32
  ole32
  uuid
  windowscodecs
)

if(MINGW)
  target_link_options(
    ${FRAME_OVERLAY_MODULE_TARGET}
    PRIVATE
    -static-libgcc
    -static-libstdc++
  )
endif()

set_target_properties(
  ${FRAME_OVERLAY_MODULE_TARGET}
  PROPERTIES
  PREFIX ""
  OUTPUT_NAME "frame-overlay-module"
)

