#set(CMAKE_BUILD_TYPE Release)
set(CMAKE_BUILD_TYPE Debug)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
cmake_minimum_required(VERSION 3.12)
project(dummyUsbDriver CXX)

# Dependencies
find_package(PkgConfig REQUIRED)

# find libusb!
pkg_check_modules (LIBUSB_PKG libusb-1.0)
find_path(LIBUSB_INCLUDE_DIR
  NAMES libusb.h
  PATHS
  ${LIBUSB_PKG_INCLUDE_DIRS}
)
find_library(LIBUSB_LIBRARY
  NAMES usb-1.0
  PATHS
  ${LIBUSB_PKG_LIBRARY_DIRS}
)

# Source & Header files
file(GLOB_RECURSE cppHeader CONFIGURE_DEPENDS
"include/*.hpp"
)

file(GLOB_RECURSE cppSrcs CONFIGURE_DEPENDS
"src/*.cpp"
)

add_executable(${PROJECT_NAME} ${cppSrcs} ${cppHeader})

# Target specific include directories
target_include_directories(${PROJECT_NAME}
PRIVATE "include/"
)
include_directories(${LIBUSB_INCLUDE_DIR})

# Target specific compile flags
if(MSVC)
  target_compile_options(${PROJECT_NAME} PRIVATE /W4)
else()
  target_compile_options(${PROJECT_NAME} PRIVATE -Wall -Wextra -pedantic)
endif()

# Link target specific libraries
target_link_libraries (${PROJECT_NAME} ${LIBUSB_LIBRARY})
