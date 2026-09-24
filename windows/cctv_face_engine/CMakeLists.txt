cmake_minimum_required(VERSION 3.14)
project(cctv_face_engine LANGUAGES CXX)

set(OPENCV_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/opencv_sdk")

add_library(cctv_face_engine SHARED
  "cctv_face_engine.cpp"
  "cctv_face_engine.h"
)

apply_standard_settings(cctv_face_engine)

target_compile_definitions(cctv_face_engine PRIVATE CCTV_FACE_ENGINE_EXPORTS)
target_include_directories(cctv_face_engine PUBLIC 
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${OPENCV_SDK_DIR}/include"
)

# Link against Debug OpenCV in Debug mode, and optimized Release OpenCV in Release/Profile modes
target_link_libraries(cctv_face_engine PRIVATE
  debug "${OPENCV_SDK_DIR}/lib/opencv_world4100d.lib"
  optimized "${OPENCV_SDK_DIR}/lib/opencv_world4100.lib"
)

# Copy DLLs and model files next to the output DLL and runner executable directory
add_custom_command(TARGET cctv_face_engine POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "$<TARGET_FILE:cctv_face_engine>"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "$<IF:$<CONFIG:Debug>,${OPENCV_SDK_DIR}/opencv_world4100d.dll,${OPENCV_SDK_DIR}/opencv_world4100.dll>"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "$<IF:$<CONFIG:Debug>,${OPENCV_SDK_DIR}/opencv_videoio_msmf4100_64d.dll,${OPENCV_SDK_DIR}/opencv_videoio_msmf4100_64.dll>"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${OPENCV_SDK_DIR}/opencv_videoio_ffmpeg4100_64.dll"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/deploy.prototxt"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/res10_300x300_ssd_iter_140000.caffemodel"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/minifasnet_v2.onnx"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/face_recognition_sface_2021dec.onnx"
    "${CMAKE_BINARY_DIR}/runner/$<CONFIG>"
)

# Install dlls and AI models right next to madarsa_app.exe in the bundle directory
if(DEFINED INSTALL_BUNDLE_LIB_DIR)
  install(TARGETS cctv_face_engine
    RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime
  )
  install(FILES 
    "$<IF:$<CONFIG:Debug>,${OPENCV_SDK_DIR}/opencv_world4100d.dll,${OPENCV_SDK_DIR}/opencv_world4100.dll>"
    "$<IF:$<CONFIG:Debug>,${OPENCV_SDK_DIR}/opencv_videoio_msmf4100_64d.dll,${OPENCV_SDK_DIR}/opencv_videoio_msmf4100_64.dll>"
    "${OPENCV_SDK_DIR}/opencv_videoio_ffmpeg4100_64.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime
  )
  install(FILES 
    "${CMAKE_CURRENT_SOURCE_DIR}/deploy.prototxt"
    "${CMAKE_CURRENT_SOURCE_DIR}/res10_300x300_ssd_iter_140000.caffemodel"
    "${CMAKE_CURRENT_SOURCE_DIR}/minifasnet_v2.onnx"
    "${CMAKE_CURRENT_SOURCE_DIR}/face_recognition_sface_2021dec.onnx"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime
  )
endif()
