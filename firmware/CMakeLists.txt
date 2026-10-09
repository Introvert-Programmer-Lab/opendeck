cmake_minimum_required(VERSION 3.16)

# One firmware per board: idf.py -B build/<board> -DOPENDECK_BOARD=<board> build
# Each board lives in boards/<board>/ (see boards/README.md).
if(NOT DEFINED OPENDECK_BOARD)
  set(OPENDECK_BOARD jc3248w535)
endif()
set(OPENDECK_BOARD_DIR ${CMAKE_CURRENT_LIST_DIR}/boards/${OPENDECK_BOARD})
if(NOT EXISTS ${OPENDECK_BOARD_DIR}/board.cmake)
  message(FATAL_ERROR "Unknown board '${OPENDECK_BOARD}'. Boards are the folders in firmware/boards.")
endif()
include(${OPENDECK_BOARD_DIR}/board.cmake)
# Components read the board from here: their dependency scan runs in a
# separate CMake process that does not see the variables above.
file(WRITE ${CMAKE_BINARY_DIR}/opendeck_board.cmake
     "set(OPENDECK_BOARD ${OPENDECK_BOARD})\nset(OPENDECK_BOARD_DIR ${OPENDECK_BOARD_DIR})\ninclude(${OPENDECK_BOARD_DIR}/board.cmake)\n")

set(IDF_TARGET ${BOARD_TARGET})
# Keep each board's sdkconfig in its own build folder.
set(SDKCONFIG ${CMAKE_BINARY_DIR}/sdkconfig)
set(SDKCONFIG_DEFAULTS
    ${CMAKE_CURRENT_LIST_DIR}/sdkconfig.defaults
    ${CMAKE_CURRENT_LIST_DIR}/config/flash_${BOARD_FLASH}.defaults
    ${CMAKE_CURRENT_LIST_DIR}/config/psram_${BOARD_PSRAM}.defaults
    ${CMAKE_CURRENT_LIST_DIR}/config/link_${BOARD_LINK}.defaults)
if(EXISTS ${OPENDECK_BOARD_DIR}/sdkconfig.defaults)
  list(APPEND SDKCONFIG_DEFAULTS ${OPENDECK_BOARD_DIR}/sdkconfig.defaults)
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(opendeck)
