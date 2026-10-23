# LAME (libmp3lame, LGPL) + puente JNI para Android.
cmake_minimum_required(VERSION 3.10)
project(media_tools LANGUAGES C)

file(GLOB LAME_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/lame/*.c)

add_library(media_tools SHARED media_tools_jni.c ${LAME_SOURCES})

target_include_directories(media_tools PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/lame)
target_compile_definitions(media_tools PRIVATE
  STDC_HEADERS=1 HAVE_STDINT_H=1 HAVE_STRING_H=1 HAVE_STDLIB_H=1 HAVE_LIMITS_H=1
  ieee754_float32_t=float)
# El código de LAME es antiguo y genera muchas advertencias que no aportan nada aquí.
target_compile_options(media_tools PRIVATE -w -O2)
target_link_libraries(media_tools m)
# Páginas de 16 KB (requisito de Android 15+ en dispositivos nuevos).
target_link_options(media_tools PRIVATE "-Wl,-z,max-page-size=16384")
