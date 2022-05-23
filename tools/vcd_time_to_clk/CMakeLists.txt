#set(CMAKE_BUILD_TYPE Release)
set(CMAKE_BUILD_TYPE Debug)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
cmake_minimum_required(VERSION 3.12)
project(vcd_time_to_clk CXX)

# Dependencies
#find_package (Threads REQUIRED)

# Source & Header files
file(GLOB_RECURSE cppHeader CONFIGURE_DEPENDS
"include/*.hpp"
"../vcd_signal_merger/include/*.hpp"
)

file(GLOB_RECURSE cppSrcs CONFIGURE_DEPENDS
"../vcd_signal_merger/include/*.cpp"
"src/*.cpp"
)

add_executable(${PROJECT_NAME} ${cppSrcs} ${cppHeader})

# Target specific include directories
target_include_directories(${PROJECT_NAME}
PRIVATE "include/"
PRIVATE "../vcd_signal_merger/include/"
)

# Target specific compile flags
if(MSVC)
  target_compile_options(${PROJECT_NAME} PRIVATE /W4)
else()
  target_compile_options(${PROJECT_NAME} PRIVATE -Wall -Wextra -pedantic)
endif()

# Link target specific libraries
#target_link_libraries (${PROJECT_NAME} ${CMAKE_THREAD_LIBS_INIT})
