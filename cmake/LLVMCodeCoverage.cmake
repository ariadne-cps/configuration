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
set(LLVM_COVERAGE_CXX_COMPILE_FLAGS "${LLVM_COVERAGE_COMPILE_FLAGS} -femit-all-decls")
set(LLVM_COVERAGE_LINK_FLAGS "-fprofile-instr-generate")

function(append_llvm_coverage_compiler_flags)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${LLVM_COVERAGE_COMPILE_FLAGS}" PARENT_SCOPE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${LLVM_COVERAGE_CXX_COMPILE_FLAGS}" PARENT_SCOPE)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LLVM_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${LLVM_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} ${LLVM_COVERAGE_LINK_FLAGS}" PARENT_SCOPE)
    message(STATUS "Appending LLVM C code coverage compiler flags: ${LLVM_COVERAGE_COMPILE_FLAGS}")
    message(STATUS "Appending LLVM CXX code coverage compiler flags: ${LLVM_COVERAGE_CXX_COMPILE_FLAGS}")
endfunction()

function(setup_target_for_coverage_llvm)
    set(options NONE)
    set(oneValueArgs NAME TARGET EXCLUDE_REGEX)
    set(multiValueArgs DEPENDENCIES OBJECTS SOURCES MODULE_NAMES MODULE_ROOTS)
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

    set(LLVM_COV_OBJECT_ARGS "")
    foreach(Coverage_OBJECT IN LISTS Coverage_OBJECTS)
        if(NOT TARGET ${Coverage_OBJECT})
            message(FATAL_ERROR "Coverage object target '${Coverage_OBJECT}' does not exist.")
        endif()
        list(APPEND LLVM_COV_OBJECT_ARGS "-object=$<TARGET_FILE:${Coverage_OBJECT}>")
    endforeach()

    set(PROFILE_DIR "${PROJECT_BINARY_DIR}/coverage/profiles")
    set(PROFDATA_FILE "${PROJECT_BINARY_DIR}/coverage/coverage.profdata")
    set(LCOV_FILE "${PROJECT_BINARY_DIR}/coverage.info")
    set(HTML_DIR "${PROJECT_BINARY_DIR}/coverage/html")
    set(BRANCH_REPORT_FILE "${PROJECT_BINARY_DIR}/coverage/branches.txt")
    set(MERGE_SCRIPT "${PROJECT_BINARY_DIR}/merge-llvm-coverage.cmake")
    set(EXPORT_SCRIPT "${PROJECT_BINARY_DIR}/export-llvm-coverage.cmake")
    set(MODULE_DIR "${PROJECT_BINARY_DIR}/coverage/modules")
    set(MODULE_SCRIPT "${PROJECT_BINARY_DIR}/export-llvm-module-coverage.cmake")

    file(WRITE "${MERGE_SCRIPT}"
"file(GLOB LLVM_RAW_PROFILES \"${PROFILE_DIR}/*.profraw\")
if(NOT LLVM_RAW_PROFILES)
    message(FATAL_ERROR \"No LLVM raw coverage profiles were generated.\")
endif()
execute_process(
    COMMAND \"${LLVM_PROFDATA_EXECUTABLE}\" merge -sparse \${LLVM_RAW_PROFILES} -o \"${PROFDATA_FILE}\"
    RESULT_VARIABLE LLVM_PROFILE_MERGE_RESULT
)
if(NOT LLVM_PROFILE_MERGE_RESULT EQUAL 0)
    message(FATAL_ERROR \"llvm-profdata merge failed.\")
endif()
")

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

    file(GENERATE OUTPUT "${EXPORT_SCRIPT}" CONTENT
"execute_process(
    COMMAND \"${LLVM_COV_EXECUTABLE}\" export
            \"$<TARGET_FILE:${Coverage_TARGET}>\"
            ${LLVM_COV_OBJECT_ARGS}
            \"-instr-profile=${PROFDATA_FILE}\"
            \"-format=lcov\"
            ${LLVM_COV_FILTER_ARGS}
            ${LLVM_COV_SOURCE_ARGS}
    OUTPUT_FILE \"${LCOV_FILE}\"
    RESULT_VARIABLE LLVM_COV_EXPORT_RESULT
)
if(NOT LLVM_COV_EXPORT_RESULT EQUAL 0)
    message(FATAL_ERROR \"llvm-cov export failed.\")
endif()
")

    if(Coverage_MODULE_NAMES)
        list(LENGTH Coverage_MODULE_NAMES _module_name_count)
        list(LENGTH Coverage_MODULE_ROOTS _module_root_count)
        if(NOT _module_name_count EQUAL _module_root_count)
            message(FATAL_ERROR "LLVM coverage module name/root list length mismatch.")
        endif()

        set(_llvm_module_script_template [=[
set(MODULE_NAMES "@Coverage_MODULE_NAMES@")
set(MODULE_ROOTS "@Coverage_MODULE_ROOTS@")
set(TARGET_PATH "$<TARGET_FILE:@Coverage_TARGET@>")
set(OBJECT_ARGS "@LLVM_COV_OBJECT_ARGS@")
set(PROFDATA_FILE "@PROFDATA_FILE@")
set(MODULE_DIR "@MODULE_DIR@")
set(FILTER_ARGS "@LLVM_COV_FILTER_ARGS@")
set(LLVM_COV_EXECUTABLE "@LLVM_COV_EXECUTABLE@")

file(REMOVE_RECURSE "${MODULE_DIR}")
file(MAKE_DIRECTORY "${MODULE_DIR}")

list(LENGTH MODULE_NAMES _module_count)
list(LENGTH MODULE_ROOTS _root_count)
if(NOT _module_count EQUAL _root_count)
    message(FATAL_ERROR "LLVM coverage module name/root list length mismatch.")
endif()

if(_module_count GREATER 0)
    math(EXPR _module_last "${_module_count} - 1")
    foreach(_index RANGE 0 ${_module_last})
        list(GET MODULE_NAMES ${_index} _module_name)
        list(GET MODULE_ROOTS ${_index} _module_root)
        string(REGEX REPLACE "[^A-Za-z0-9_.-]" "_" _module_slug "${_module_name}")

        set(_module_sources)
        foreach(_source_dir include src)
            if(EXISTS "${_module_root}/${_source_dir}")
                file(GLOB_RECURSE _source_files
                    LIST_DIRECTORIES false
                    "${_module_root}/${_source_dir}/*.c"
                    "${_module_root}/${_source_dir}/*.cc"
                    "${_module_root}/${_source_dir}/*.cpp"
                    "${_module_root}/${_source_dir}/*.cxx"
                    "${_module_root}/${_source_dir}/*.h"
                    "${_module_root}/${_source_dir}/*.hh"
                    "${_module_root}/${_source_dir}/*.hpp"
                    "${_module_root}/${_source_dir}/*.hxx"
                )
                list(APPEND _module_sources ${_source_files})
            endif()
        endforeach()

        if(NOT _module_sources)
            message(FATAL_ERROR "No coverage sources found for module '${_module_name}'.")
        endif()

        set(_module_dir "${MODULE_DIR}/${_module_slug}")
        set(_module_info "${_module_dir}/coverage.info")
        set(_module_html "${_module_dir}/html")
        set(_module_summary "${_module_dir}/summary.txt")
        file(MAKE_DIRECTORY "${_module_dir}")

        execute_process(
            COMMAND "${LLVM_COV_EXECUTABLE}" report
                    "${TARGET_PATH}"
                    ${OBJECT_ARGS}
                    "-instr-profile=${PROFDATA_FILE}"
                    ${FILTER_ARGS}
                    ${_module_sources}
            OUTPUT_VARIABLE _report_output
            RESULT_VARIABLE _report_result
            ERROR_VARIABLE _report_error
        )
        if(NOT _report_result EQUAL 0)
            message(FATAL_ERROR
                "llvm-cov report failed for module '${_module_name}':\n${_report_error}")
        endif()
        file(WRITE "${_module_summary}" "${_report_output}")
        message("")
        message("===== Coverage module: ${_module_name} =====")
        message("${_report_output}")

        execute_process(
            COMMAND "${LLVM_COV_EXECUTABLE}" export
                    "${TARGET_PATH}"
                    ${OBJECT_ARGS}
                    "-instr-profile=${PROFDATA_FILE}"
                    "-format=lcov"
                    ${FILTER_ARGS}
                    ${_module_sources}
            OUTPUT_FILE "${_module_info}"
            RESULT_VARIABLE _export_result
            ERROR_VARIABLE _export_error
        )
        if(NOT _export_result EQUAL 0)
            message(FATAL_ERROR
                "llvm-cov export failed for module '${_module_name}':\n${_export_error}")
        endif()

        file(MAKE_DIRECTORY "${_module_html}")
        execute_process(
            COMMAND "${LLVM_COV_EXECUTABLE}" show
                    "${TARGET_PATH}"
                    ${OBJECT_ARGS}
                    "-instr-profile=${PROFDATA_FILE}"
                    "-format=html"
                    "-show-branches=count"
                    "-output-dir=${_module_html}"
                    ${FILTER_ARGS}
                    ${_module_sources}
            RESULT_VARIABLE _html_result
            ERROR_VARIABLE _html_error
        )
        if(NOT _html_result EQUAL 0)
            message(FATAL_ERROR
                "llvm-cov HTML generation failed for module '${_module_name}':\n${_html_error}")
        endif()
    endforeach()
endif()
]=])
        string(CONFIGURE "${_llvm_module_script_template}" _llvm_module_script @ONLY)
        file(GENERATE OUTPUT "${MODULE_SCRIPT}" CONTENT "${_llvm_module_script}")
    endif()

    set(_module_coverage_command)
    if(Coverage_MODULE_NAMES)
        set(_module_coverage_command
            COMMAND "${CMAKE_COMMAND}" -P "${MODULE_SCRIPT}"
        )
    endif()

    add_custom_target(${Coverage_NAME}
        COMMAND "${CMAKE_COMMAND}" -E rm -rf "${PROJECT_BINARY_DIR}/coverage"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROFILE_DIR}"
        COMMAND "${CMAKE_COMMAND}" -E env
                "LLVM_PROFILE_FILE=${PROFILE_DIR}/%p-%m.profraw"
                "${CMAKE_CTEST_COMMAND}" --output-on-failure
        COMMAND "${CMAKE_COMMAND}" -P "${MERGE_SCRIPT}"
        COMMAND "${CMAKE_COMMAND}" -P "${EXPORT_SCRIPT}"
        COMMAND "${LLVM_COV_EXECUTABLE}" show
                "$<TARGET_FILE:${Coverage_TARGET}>"
                ${LLVM_COV_OBJECT_ARGS}
                "-instr-profile=${PROFDATA_FILE}"
                "-show-branches=count"
                "-show-line-counts-or-regions"
                ${LLVM_COV_FILTER_ARGS}
                ${LLVM_COV_SOURCE_ARGS}
                > "${BRANCH_REPORT_FILE}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${HTML_DIR}"
        COMMAND "${LLVM_COV_EXECUTABLE}" show
                "$<TARGET_FILE:${Coverage_TARGET}>"
                ${LLVM_COV_OBJECT_ARGS}
                "-instr-profile=${PROFDATA_FILE}"
                "-format=html"
                "-show-branches=count"
                "-output-dir=${HTML_DIR}"
                ${LLVM_COV_FILTER_ARGS}
                ${LLVM_COV_SOURCE_ARGS}
        ${_module_coverage_command}
        WORKING_DIRECTORY "${PROJECT_BINARY_DIR}"
        DEPENDS ${Coverage_DEPENDENCIES} ${Coverage_TARGET} ${Coverage_OBJECTS}
        VERBATIM
        COMMENT "Running tests and generating LLVM code coverage report."
    )

endfunction()
