include_guard(GLOBAL)

include(CMakeParseArguments)

macro(enable_project_coverage)
    if(COVERAGE)
        if(APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
            include(LLVMCodeCoverage)
            append_llvm_coverage_compiler_flags()
        elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
            include(GCCCodeCoverage)
            append_gcc_coverage_compiler_flags()
        else()
            message(FATAL_ERROR
                "Coverage is supported only with GCC or macOS AppleClang/Clang.")
        endif()
    endif()
endmacro()

function(setup_project_coverage)
    if(NOT COVERAGE)
        return()
    endif()

    set(options)
    set(oneValueArgs TARGET TEST_TARGET EXCLUDE_REGEX)
    set(multiValueArgs SOURCES COVERAGE_TARGETS)
    cmake_parse_arguments(COVERAGE_SETUP
        "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT COVERAGE_SETUP_TARGET)
        message(FATAL_ERROR "setup_project_coverage requires TARGET.")
    endif()
    if(NOT COVERAGE_SETUP_TEST_TARGET)
        message(FATAL_ERROR "setup_project_coverage requires TEST_TARGET.")
    endif()
    if(NOT TARGET ${COVERAGE_SETUP_TARGET})
        message(FATAL_ERROR "Coverage target '${COVERAGE_SETUP_TARGET}' does not exist.")
    endif()
    if(NOT TARGET ${COVERAGE_SETUP_TEST_TARGET})
        message(FATAL_ERROR "Test aggregate target '${COVERAGE_SETUP_TEST_TARGET}' does not exist.")
    endif()

    if(APPLE AND CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
        set(_coverage_objects ${COVERAGE_SETUP_COVERAGE_TARGETS})

        if(NOT _coverage_objects)
            get_property(_test_dependencies
                TARGET ${COVERAGE_SETUP_TEST_TARGET}
                PROPERTY MANUALLY_ADDED_DEPENDENCIES)

            foreach(_test_target IN LISTS _test_dependencies)
                if(TARGET ${_test_target})
                    get_target_property(_test_target_type ${_test_target} TYPE)
                    if(_test_target_type STREQUAL "EXECUTABLE")
                        list(APPEND _coverage_objects ${_test_target})
                    endif()
                endif()
            endforeach()
        endif()

        set(_llvm_args
            NAME coverage
            TARGET ${COVERAGE_SETUP_TARGET}
            OBJECTS ${_coverage_objects}
            DEPENDENCIES ${COVERAGE_SETUP_TEST_TARGET}
            SOURCES ${COVERAGE_SETUP_SOURCES}
        )
        if(COVERAGE_SETUP_EXCLUDE_REGEX)
            list(APPEND _llvm_args EXCLUDE_REGEX "${COVERAGE_SETUP_EXCLUDE_REGEX}")
        endif()

        setup_target_for_coverage_llvm(${_llvm_args})
    else()
        setup_target_for_coverage_gcc(
            NAME coverage
            DEPENDENCIES ${COVERAGE_SETUP_TEST_TARGET}
        )
    endif()
endfunction()

macro(setup_standalone_project_tests)
    set(options EXCLUDE_FROM_ALL)
    set(oneValueArgs TARGET TEST_DIRECTORY TEST_TARGET EXCLUDE_REGEX)
    set(multiValueArgs SOURCES TEST_BUILD_DEPENDENCIES COVERAGE_TARGETS)
    cmake_parse_arguments(TEST_SETUP
        "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT TEST_SETUP_TARGET)
        message(FATAL_ERROR "setup_standalone_project_tests requires TARGET.")
    endif()
    if(NOT TEST_SETUP_TEST_DIRECTORY)
        message(FATAL_ERROR "setup_standalone_project_tests requires TEST_DIRECTORY.")
    endif()
    if(NOT TEST_SETUP_TEST_TARGET)
        message(FATAL_ERROR "setup_standalone_project_tests requires TEST_TARGET.")
    endif()

    enable_testing()

    if(TEST_SETUP_EXCLUDE_FROM_ALL)
        add_subdirectory("${TEST_SETUP_TEST_DIRECTORY}" EXCLUDE_FROM_ALL)
    else()
        add_subdirectory("${TEST_SETUP_TEST_DIRECTORY}")
    endif()

    if(NOT TARGET ${TEST_SETUP_TEST_TARGET})
        message(FATAL_ERROR
            "Test directory '${TEST_SETUP_TEST_DIRECTORY}' did not create target '${TEST_SETUP_TEST_TARGET}'.")
    endif()

    if(TEST_SETUP_TEST_BUILD_DEPENDENCIES)
        add_dependencies(${TEST_SETUP_TEST_TARGET} ${TEST_SETUP_TEST_BUILD_DEPENDENCIES})
    endif()

    setup_project_coverage(
        TARGET ${TEST_SETUP_TARGET}
        TEST_TARGET ${TEST_SETUP_TEST_TARGET}
        SOURCES ${TEST_SETUP_SOURCES}
        COVERAGE_TARGETS ${TEST_SETUP_COVERAGE_TARGETS}
        EXCLUDE_REGEX "${TEST_SETUP_EXCLUDE_REGEX}"
    )
endmacro()
