include(FetchContent)

set(LIBOPENCM3_GIT_TAG master CACHE STRING "libopencm3 git tag/branch")

FetchContent_Declare(
    libopencm3
    GIT_REPOSITORY https://github.com/libopencm3/libopencm3.git
    GIT_TAG ${LIBOPENCM3_GIT_TAG}
    GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(libopencm3)

set(LIBOPENCM3_DIR ${libopencm3_SOURCE_DIR})
set(LIBOPENCM3_LIBRARY ${LIBOPENCM3_DIR}/lib/libopencm3_stm32f1.a)

add_custom_command(
    OUTPUT ${LIBOPENCM3_LIBRARY}
    COMMAND make TARGETS=stm32/f1
    WORKING_DIRECTORY ${LIBOPENCM3_DIR}
    COMMENT "Building libopencm3"
    VERBATIM
)

add_custom_target(libopencm3_build DEPENDS ${LIBOPENCM3_LIBRARY})
