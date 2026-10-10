include(CMakeParseArguments)

find_program(LCOV_EXECUTABLE NAMES lcov REQUIRED)
find_program(GENHTML_EXECUTABLE NAMES genhtml REQUIRED)

set(GCC_COVERAGE_COMPILE_FLAGS "--coverage -fprofile-update=atomic")
set(GCC_COVERAGE_LINK_FLAGS "--coverage")

function(append_gcc_coverage_compiler_flags)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${GCC_COVERAGE_COMPILE_FLAGS}" PARENT_SCOPE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${GCC_COVERAGE_COMPILE_FLAGS}" PARENT_SCOPE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${GCC_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${GCC_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${GCC_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    message(STATUS "Appending GCC code coverage compiler flags: ${GCC_COVERAGE_COMPILE_FLAGS}")
endfunction()

function(setup_target_for_coverage_gcc)
    set(options NONE)
    set(oneValueArgs NAME EXCLUDE_REGEX)
    set(multiValueArgs DEPENDENCIES SOURCES MODULE_NAMES MODULE_ROOTS)
    cmake_parse_arguments(Coverage "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT Coverage_NAME)
        message(FATAL_ERROR "setup_target_for_coverage_gcc requires NAME.")
    endif()

    set(COVERAGE_INFO "${PROJECT_BINARY_DIR}/${Coverage_NAME}.info")
    set(COVERAGE_HTML_DIR "${PROJECT_BINARY_DIR}/${Coverage_NAME}")
    set(MODULE_DIR "${PROJECT_BINARY_DIR}/coverage/modules")
    set(MODULE_SCRIPT "${PROJECT_BINARY_DIR}/export-gcc-module-coverage.cmake")

    set(_capture_filter_args)
    foreach(_source IN LISTS Coverage_SOURCES)
        list(APPEND _capture_filter_args --include "${_source}/*")
    endforeach()

    if(Coverage_MODULE_NAMES)
        list(LENGTH Coverage_MODULE_NAMES _module_name_count)
        list(LENGTH Coverage_MODULE_ROOTS _module_root_count)
        if(NOT _module_name_count EQUAL _module_root_count)
            message(FATAL_ERROR "GCC coverage module name/root list length mismatch.")
        endif()

        set(_gcc_module_script_template [=[
set(MODULE_NAMES "@Coverage_MODULE_NAMES@")
set(MODULE_ROOTS "@Coverage_MODULE_ROOTS@")
set(COVERAGE_INFO "@COVERAGE_INFO@")
set(MODULE_DIR "@MODULE_DIR@")
set(LCOV_EXECUTABLE "@LCOV_EXECUTABLE@")
set(GENHTML_EXECUTABLE "@GENHTML_EXECUTABLE@")

file(REMOVE_RECURSE "${MODULE_DIR}")
file(MAKE_DIRECTORY "${MODULE_DIR}")

list(LENGTH MODULE_NAMES _module_count)
list(LENGTH MODULE_ROOTS _root_count)
if(NOT _module_count EQUAL _root_count)
    message(FATAL_ERROR "GCC coverage module name/root list length mismatch.")
endif()

if(_module_count GREATER 0)
    math(EXPR _module_last "${_module_count} - 1")
    foreach(_index RANGE 0 ${_module_last})
        list(GET MODULE_NAMES ${_index} _module_name)
        list(GET MODULE_ROOTS ${_index} _module_root)
        string(REGEX REPLACE "[^A-Za-z0-9_.-]" "_" _module_slug "${_module_name}")

        set(_module_patterns)
        if(EXISTS "${_module_root}/include")
            list(APPEND _module_patterns "${_module_root}/include/*")
        endif()
        if(EXISTS "${_module_root}/src")
            list(APPEND _module_patterns "${_module_root}/src/*")
        endif()
        if(NOT _module_patterns)
            message(FATAL_ERROR "No coverage sources found for module '${_module_name}'.")
        endif()

        set(_module_dir "${MODULE_DIR}/${_module_slug}")
        set(_module_info "${_module_dir}/coverage.info")
        set(_module_html "${_module_dir}/html")
        set(_module_summary "${_module_dir}/summary.txt")
        file(MAKE_DIRECTORY "${_module_dir}")

        execute_process(
            COMMAND "${LCOV_EXECUTABLE}"
                    --extract "${COVERAGE_INFO}"
                    ${_module_patterns}
                    --output-file "${_module_info}"
            RESULT_VARIABLE _extract_result
            ERROR_VARIABLE _extract_error
        )
        if(NOT _extract_result EQUAL 0)
            message(FATAL_ERROR
                "lcov extraction failed for module '${_module_name}':\n${_extract_error}")
        endif()

        execute_process(
            COMMAND "${LCOV_EXECUTABLE}" --list "${_module_info}"
            OUTPUT_VARIABLE _list_output
            RESULT_VARIABLE _list_result
            ERROR_VARIABLE _list_error
        )
        if(NOT _list_result EQUAL 0)
            message(FATAL_ERROR
                "lcov listing failed for module '${_module_name}':\n${_list_error}")
        endif()
        file(WRITE "${_module_summary}" "${_list_output}")
        message("")
        message("===== Coverage module: ${_module_name} =====")
        message("${_list_output}")

        execute_process(
            COMMAND "${GENHTML_EXECUTABLE}"
                    --output-directory "${_module_html}"
                    "${_module_info}"
            RESULT_VARIABLE _html_result
            ERROR_VARIABLE _html_error
        )
        if(NOT _html_result EQUAL 0)
            message(FATAL_ERROR
                "genhtml failed for module '${_module_name}':\n${_html_error}")
        endif()
    endforeach()
endif()
]=])
        string(CONFIGURE "${_gcc_module_script_template}" _gcc_module_script @ONLY)
        file(GENERATE OUTPUT "${MODULE_SCRIPT}" CONTENT "${_gcc_module_script}")
    endif()

    add_custom_target(${Coverage_NAME}
        COMMAND "${LCOV_EXECUTABLE}"
                --directory "${PROJECT_BINARY_DIR}"
                --zerocounters
        COMMAND "${CMAKE_CTEST_COMMAND}" --output-on-failure
        COMMAND "${LCOV_EXECUTABLE}"
                --directory "${PROJECT_BINARY_DIR}"
                --capture
                ${_capture_filter_args}
                --output-file "${COVERAGE_INFO}"
        COMMAND "${GENHTML_EXECUTABLE}"
                --output-directory "${COVERAGE_HTML_DIR}"
                "${COVERAGE_INFO}"
        WORKING_DIRECTORY "${PROJECT_BINARY_DIR}"
        DEPENDS ${Coverage_DEPENDENCIES}
        VERBATIM
        COMMENT "Running tests and generating GCC/lcov code coverage report."
    )

    if(Coverage_EXCLUDE_REGEX)
        add_custom_command(TARGET ${Coverage_NAME} POST_BUILD
            COMMAND "${LCOV_EXECUTABLE}"
                    --remove "${COVERAGE_INFO}" "${Coverage_EXCLUDE_REGEX}"
                    --output-file "${COVERAGE_INFO}"
            VERBATIM
        )
    endif()

    if(Coverage_MODULE_NAMES)
        add_custom_command(TARGET ${Coverage_NAME} POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -P "${MODULE_SCRIPT}"
            VERBATIM
        )
    endif()
endfunction()
