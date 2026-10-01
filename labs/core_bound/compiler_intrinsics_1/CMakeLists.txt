cmake_minimum_required(VERSION 3.25)

project(lab LANGUAGES C CXX)

if(CMAKE_CURRENT_SOURCE_DIR MATCHES "^(.*)[/\\\\]labs[/\\\\].*$")
  set(REPO_ROOT "${CMAKE_MATCH_1}")
else()
  get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
  if(NOT EXISTS "${REPO_ROOT}/tools/labs.cmake")
    get_filename_component(REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
  endif()
endif()

include(${REPO_ROOT}/tools/labs.cmake)
