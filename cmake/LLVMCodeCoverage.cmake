include(CMakeParseArguments)

find_program(XCRUN_EXECUTABLE xcrun)
if(NOT XCRUN_EXECUTABLE)
    message(FATAL_ERROR "xcrun not found; LLVM coverage on macOS requires the Xcode command line tools.")
endif()

execute_process(
    COMMAND "${XCRUN_EXECUTABLE}" --find llvm-profdata
    RESULT_VARIABLE LLVM_PROFDATA_RESULT
    OUTPUT_VARIABLE LLVM_PROFDATA_EXECUTABLE
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT LLVM_PROFDATA_RESULT EQUAL 0 OR NOT LLVM_PROFDATA_EXECUTABLE)
    message(FATAL_ERROR "llvm-profdata not found via xcrun.")
endif()

execute_process(
    COMMAND "${XCRUN_EXECUTABLE}" --find llvm-cov
    RESULT_VARIABLE LLVM_COV_RESULT
    OUTPUT_VARIABLE LLVM_COV_EXECUTABLE
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT LLVM_COV_RESULT EQUAL 0 OR NOT LLVM_COV_EXECUTABLE)
    message(FATAL_ERROR "llvm-cov not found via xcrun.")
endif()

set(LLVM_COVERAGE_COMPILE_FLAGS "-fprofile-instr-generate -fcoverage-mapping")
set(LLVM_COVERAGE_LINK_FLAGS "-fprofile-instr-generate")

function(append_llvm_coverage_compiler_flags)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${LLVM_COVERAGE_COMPILE_FLAGS}" PARENT_SCOPE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${LLVM_COVERAGE_COMPILE_FLAGS}" PARENT_SCOPE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LLVM_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${LLVM_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${LLVM_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    message(STATUS "Appending LLVM code coverage compiler flags: ${LLVM_COVERAGE_COMPILE_FLAGS}")
endfunction()

function(setup_target_for_coverage_llvm)
    set(options NONE)
    set(oneValueArgs NAME TARGET EXCLUDE_REGEX)
    set(multiValueArgs DEPENDENCIES OBJECTS SOURCES)
    cmake_parse_arguments(Coverage "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT Coverage_NAME)
        message(FATAL_ERROR "setup_target_for_coverage_llvm requires NAME.")
    endif()
    if(NOT Coverage_TARGET)
        message(FATAL_ERROR "setup_target_for_coverage_llvm requires TARGET.")
    endif()
    if(NOT TARGET ${Coverage_TARGET})
        message(FATAL_ERROR "Coverage target '${Coverage_TARGET}' does not exist.")
    endif()

    set(LLVM_COV_TEST_PATHS "")
    foreach(Coverage_OBJECT IN LISTS Coverage_OBJECTS)
        if(NOT TARGET ${Coverage_OBJECT})
            message(FATAL_ERROR "Coverage object target '${Coverage_OBJECT}' does not exist.")
        endif()
        list(APPEND LLVM_COV_TEST_PATHS "$<TARGET_FILE:${Coverage_OBJECT}>")
    endforeach()

    set(PROFILE_DIR "${PROJECT_BINARY_DIR}/coverage/profiles")
    set(REPORT_DIR "${PROJECT_BINARY_DIR}/coverage/reports")
    set(HTML_DIR "${PROJECT_BINARY_DIR}/coverage/html")
    set(BRANCH_REPORT_FILE "${PROJECT_BINARY_DIR}/coverage/branches.txt")
    set(LCOV_FILE "${PROJECT_BINARY_DIR}/coverage.info")
    set(RUN_SCRIPT "${PROJECT_BINARY_DIR}/run-llvm-coverage.cmake")

    set(LLVM_COV_SOURCE_ARGS "")
    foreach(Coverage_SOURCE IN LISTS Coverage_SOURCES)
        if(IS_DIRECTORY "${Coverage_SOURCE}")
            file(GLOB_RECURSE _coverage_source_files
                CONFIGURE_DEPENDS
                LIST_DIRECTORIES false
                "${Coverage_SOURCE}/*.c"
                "${Coverage_SOURCE}/*.cc"
                "${Coverage_SOURCE}/*.cpp"
                "${Coverage_SOURCE}/*.cxx"
                "${Coverage_SOURCE}/*.h"
                "${Coverage_SOURCE}/*.hh"
                "${Coverage_SOURCE}/*.hpp"
                "${Coverage_SOURCE}/*.hxx"
            )
            list(APPEND LLVM_COV_SOURCE_ARGS ${_coverage_source_files})
        else()
            list(APPEND LLVM_COV_SOURCE_ARGS "${Coverage_SOURCE}")
        endif()
    endforeach()

    set(LLVM_COV_FILTER_ARGS "")
    if(Coverage_EXCLUDE_REGEX)
        list(APPEND LLVM_COV_FILTER_ARGS "-ignore-filename-regex=${Coverage_EXCLUDE_REGEX}")
    endif()

    set(_llvm_coverage_driver_template [=[
set(TEST_NAMES "@Coverage_OBJECTS@")
set(TEST_PATHS "@LLVM_COV_TEST_PATHS@")
set(TARGET_PATH "$<TARGET_FILE:@Coverage_TARGET@>")
set(PROFILE_DIR "@PROFILE_DIR@")
set(REPORT_DIR "@REPORT_DIR@")
set(HTML_DIR "@HTML_DIR@")
set(BRANCH_REPORT_FILE "@BRANCH_REPORT_FILE@")
set(LCOV_FILE "@LCOV_FILE@")
set(SOURCE_ARGS "@LLVM_COV_SOURCE_ARGS@")
set(FILTER_ARGS "@LLVM_COV_FILTER_ARGS@")
set(LLVM_PROFDATA_EXECUTABLE "@LLVM_PROFDATA_EXECUTABLE@")
set(LLVM_COV_EXECUTABLE "@LLVM_COV_EXECUTABLE@")
set(CMAKE_CTEST_COMMAND "@CMAKE_CTEST_COMMAND@")
set(PROJECT_BINARY_DIR "@PROJECT_BINARY_DIR@")

file(REMOVE_RECURSE "${PROFILE_DIR}" "${REPORT_DIR}" "${HTML_DIR}")
file(MAKE_DIRECTORY "${PROFILE_DIR}" "${REPORT_DIR}" "${HTML_DIR}")
file(WRITE "${BRANCH_REPORT_FILE}" "")
file(WRITE "${LCOV_FILE}" "")
file(WRITE "${HTML_DIR}/index.html"
    "<!doctype html><html><body><h1>LLVM coverage by test</h1><ul>")

list(LENGTH TEST_NAMES _test_count)
list(LENGTH TEST_PATHS _path_count)
if(NOT _test_count EQUAL _path_count)
    message(FATAL_ERROR "LLVM coverage test target/path list length mismatch.")
endif()
if(_test_count EQUAL 0)
    message(FATAL_ERROR "LLVM coverage has no test executables.")
endif()

math(EXPR _last_test "${_test_count} - 1")
foreach(_index RANGE 0 ${_last_test})
    list(GET TEST_NAMES ${_index} _test_name)
    list(GET TEST_PATHS ${_index} _test_path)
    string(REGEX REPLACE "[^A-Za-z0-9_.-]" "_" _test_slug "${_test_name}")

    set(_profile_pattern "${PROFILE_DIR}/${_test_slug}-%p-%m.profraw")
    set(_profdata_file "${PROFILE_DIR}/${_test_slug}.profdata")
    set(_lcov_file "${REPORT_DIR}/${_test_slug}.info")
    set(_html_dir "${HTML_DIR}/${_test_slug}")

    message(STATUS "Running LLVM coverage test: ${_test_name}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env
                "LLVM_PROFILE_FILE=${_profile_pattern}"
                "${CMAKE_CTEST_COMMAND}" --output-on-failure -R "^${_test_name}$"
        WORKING_DIRECTORY "${PROJECT_BINARY_DIR}"
        RESULT_VARIABLE _test_result
    )
    if(NOT _test_result EQUAL 0)
        message(FATAL_ERROR "CTest failed for '${_test_name}'.")
    endif()

    file(GLOB _raw_profiles "${PROFILE_DIR}/${_test_slug}-*.profraw")
    if(NOT _raw_profiles)
        message(FATAL_ERROR "No LLVM raw coverage profiles were generated for '${_test_name}'.")
    endif()

    execute_process(
        COMMAND "${LLVM_PROFDATA_EXECUTABLE}" merge -sparse
                ${_raw_profiles}
                -o "${_profdata_file}"
        RESULT_VARIABLE _merge_result
    )
    if(NOT _merge_result EQUAL 0)
        message(FATAL_ERROR "llvm-profdata merge failed for '${_test_name}'.")
    endif()

    execute_process(
        COMMAND "${LLVM_COV_EXECUTABLE}" report
                "${TARGET_PATH}"
                "-object=${_test_path}"
                "-instr-profile=${_profdata_file}"
                ${FILTER_ARGS}
                ${SOURCE_ARGS}
        RESULT_VARIABLE _report_result
        ERROR_VARIABLE _report_error
    )
    if(_report_error MATCHES "mismatched data")
        message(FATAL_ERROR "llvm-cov reported mismatched data for '${_test_name}':\n${_report_error}")
    elseif(_report_error)
        message(WARNING "${_report_error}")
    endif()
    if(NOT _report_result EQUAL 0)
        message(FATAL_ERROR "llvm-cov report failed for '${_test_name}'.")
    endif()

    execute_process(
        COMMAND "${LLVM_COV_EXECUTABLE}" export
                "${TARGET_PATH}"
                "-object=${_test_path}"
                "-instr-profile=${_profdata_file}"
                "-format=lcov"
                ${FILTER_ARGS}
                ${SOURCE_ARGS}
        OUTPUT_FILE "${_lcov_file}"
        RESULT_VARIABLE _export_result
    )
    if(NOT _export_result EQUAL 0)
        message(FATAL_ERROR "llvm-cov export failed for '${_test_name}'.")
    endif()

    file(READ "${_lcov_file}" _lcov_content)
    file(APPEND "${LCOV_FILE}" "${_lcov_content}")

    execute_process(
        COMMAND "${LLVM_COV_EXECUTABLE}" show
                "${TARGET_PATH}"
                "-object=${_test_path}"
                "-instr-profile=${_profdata_file}"
                "-show-branches=count"
                "-show-line-counts-or-regions"
                ${FILTER_ARGS}
                ${SOURCE_ARGS}
        OUTPUT_VARIABLE _branch_output
        RESULT_VARIABLE _branch_result
    )
    if(NOT _branch_result EQUAL 0)
        message(FATAL_ERROR "llvm-cov branch report failed for '${_test_name}'.")
    endif()
    file(APPEND "${BRANCH_REPORT_FILE}"
        "===== ${_test_name} =====\n${_branch_output}\n")

    file(MAKE_DIRECTORY "${_html_dir}")
    execute_process(
        COMMAND "${LLVM_COV_EXECUTABLE}" show
                "${TARGET_PATH}"
                "-object=${_test_path}"
                "-instr-profile=${_profdata_file}"
                "-format=html"
                "-show-branches=count"
                "-output-dir=${_html_dir}"
                ${FILTER_ARGS}
                ${SOURCE_ARGS}
        RESULT_VARIABLE _html_result
    )
    if(NOT _html_result EQUAL 0)
        message(FATAL_ERROR "llvm-cov HTML report failed for '${_test_name}'.")
    endif()

    file(APPEND "${HTML_DIR}/index.html"
        "<li><a href='${_test_slug}/index.html'>${_test_name}</a></li>")
endforeach()

file(APPEND "${HTML_DIR}/index.html" "</ul></body></html>")
]=])

    string(CONFIGURE "${_llvm_coverage_driver_template}" _llvm_coverage_driver @ONLY)
    file(GENERATE OUTPUT "${RUN_SCRIPT}" CONTENT "${_llvm_coverage_driver}")

    add_custom_target(${Coverage_NAME}
        COMMAND "${CMAKE_COMMAND}" -P "${RUN_SCRIPT}"
        WORKING_DIRECTORY "${PROJECT_BINARY_DIR}"
        DEPENDS ${Coverage_DEPENDENCIES} ${Coverage_TARGET} ${Coverage_OBJECTS}
        VERBATIM
        COMMENT "Running tests and generating per-test LLVM code coverage reports."
    )

    add_custom_command(TARGET ${Coverage_NAME} POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E echo
                "LLVM coverage LCOV reports: ${REPORT_DIR}"
        COMMAND "${CMAKE_COMMAND}" -E echo
                "LLVM aggregate LCOV trace: ${LCOV_FILE}"
        COMMAND "${CMAKE_COMMAND}" -E echo
                "LLVM coverage HTML index: ${HTML_DIR}/index.html"
        COMMAND "${CMAKE_COMMAND}" -E echo
                "LLVM branch detail report: ${BRANCH_REPORT_FILE}"
    )
endfunction()
