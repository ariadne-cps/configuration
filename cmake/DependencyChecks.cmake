include_guard(GLOBAL)

find_package(Git REQUIRED)
include(CMakeParseArguments)

function(_ariadne_resolve_submodule_path REPOSITORY NAME OUTPUT_VARIABLE)
    set(_gitmodules "${REPOSITORY}/.gitmodules")
    if(NOT EXISTS "${_gitmodules}")
        message(FATAL_ERROR
            "Repository ${REPOSITORY} has no .gitmodules while resolving '${NAME}'.")
    endif()

    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_gitmodules}")

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" config --file "${_gitmodules}"
                --get-regexp "^submodule\\..*\\.path$"
        OUTPUT_VARIABLE _paths_output
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _paths_error
        RESULT_VARIABLE _paths_result
    )
    if(NOT _paths_result EQUAL 0)
        message(FATAL_ERROR
            "Cannot read submodule paths from ${_gitmodules}: ${_paths_error}")
    endif()

    string(REPLACE "\n" ";" _path_lines "${_paths_output}")
    set(_matches)
    foreach(_line IN LISTS _path_lines)
        if(_line MATCHES "^[^ \t]+[ \t]+(.+)$")
            set(_path "${CMAKE_MATCH_1}")
            get_filename_component(_basename "${_path}" NAME)
            if(_basename STREQUAL "${NAME}")
                list(APPEND _matches "${_path}")
            endif()
        endif()
    endforeach()

    list(LENGTH _matches _match_count)
    if(NOT _match_count EQUAL 1)
        message(FATAL_ERROR
            "Submodule name '${NAME}' resolves to ${_match_count} paths in "
            "${_gitmodules}; expected exactly one.")
    endif()

    list(GET _matches 0 _path)
    set(${OUTPUT_VARIABLE} "${_path}" PARENT_SCOPE)
endfunction()

function(_ariadne_ensure_submodule_initialized REPOSITORY NAME OUTPUT_DIRECTORY)
    _ariadne_resolve_submodule_path("${REPOSITORY}" "${NAME}" _path)

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}" submodule status -- "${_path}"
        OUTPUT_VARIABLE _status
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _status_error
        RESULT_VARIABLE _status_result
    )
    if(NOT _status_result EQUAL 0)
        message(FATAL_ERROR
            "Cannot inspect submodule ${REPOSITORY}/${_path}: ${_status_error}")
    endif()

    if(_status MATCHES "^[-+]")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                    submodule update --init -- "${_path}"
            ERROR_VARIABLE _update_error
            RESULT_VARIABLE _update_result
        )
        if(NOT _update_result EQUAL 0)
            message(FATAL_ERROR
                "Cannot initialize submodule ${REPOSITORY}/${_path}: ${_update_error}")
        endif()
        message(STATUS "Initialized submodule ${REPOSITORY}/${_path}")
    endif()

    set(${OUTPUT_DIRECTORY} "${REPOSITORY}/${_path}" PARENT_SCOPE)
endfunction()

function(ensure_submodule_initialized NAME)
    set(options)
    set(oneValueArgs REPOSITORY)
    cmake_parse_arguments(
        SUBMODULE "${options}" "${oneValueArgs}" "" ${ARGN})

    if(SUBMODULE_REPOSITORY)
        set(_repository "${SUBMODULE_REPOSITORY}")
    else()
        set(_repository "${PROJECT_SOURCE_DIR}")
    endif()

    _ariadne_ensure_submodule_initialized(
        "${_repository}" "${NAME}" _directory)
endfunction()

function(get_gitlink_commit REPOSITORY SUBMODULE_PATH OUTPUT_VARIABLE)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}"
                rev-parse "HEAD:${SUBMODULE_PATH}"
        OUTPUT_VARIABLE _commit
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_VARIABLE _error
        RESULT_VARIABLE _result
    )
    if(NOT _result EQUAL 0 OR _commit STREQUAL "")
        message(FATAL_ERROR
            "Cannot determine gitlink for ${REPOSITORY}/${SUBMODULE_PATH}: ${_error}")
    endif()
    set(${OUTPUT_VARIABLE} "${_commit}" PARENT_SCOPE)
endfunction()

function(require_same_dependency_commit NAME)
    set(options)
    set(oneValueArgs)
    set(multiValueArgs CHAINS)
    cmake_parse_arguments(
        CHECK "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT CHECK_CHAINS)
        message(FATAL_ERROR
            "require_same_dependency_commit(${NAME}) requires CHAINS.")
    endif()

    set(_expected "")
    set(_terminal_name "")
    set(_details "")

    foreach(_chain IN LISTS CHECK_CHAINS)
        string(REPLACE "|" ";" _tokens "${_chain}")
        list(LENGTH _tokens _token_count)
        if(_token_count EQUAL 0)
            message(FATAL_ERROR "Invalid empty dependency chain for ${NAME}.")
        endif()

        math(EXPR _last_index "${_token_count} - 1")
        list(GET _tokens ${_last_index} _chain_terminal)

        if(_terminal_name STREQUAL "")
            set(_terminal_name "${_chain_terminal}")
        elseif(NOT _terminal_name STREQUAL _chain_terminal)
            message(FATAL_ERROR
                "All ${NAME} CHAINS must terminate at the same dependency.")
        endif()

        set(_repository "${PROJECT_SOURCE_DIR}")
        set(_index 0)
        foreach(_token IN LISTS _tokens)
            if(_index EQUAL _last_index)
                _ariadne_resolve_submodule_path(
                    "${_repository}" "${_token}" _path)
                get_gitlink_commit("${_repository}" "${_path}" _commit)
            else()
                _ariadne_ensure_submodule_initialized(
                    "${_repository}" "${_token}" _repository)
            endif()
            math(EXPR _index "${_index} + 1")
        endforeach()

        string(APPEND _details "  ${_chain}: ${_commit}\n")

        if(_expected STREQUAL "")
            set(_expected "${_commit}")
        elseif(NOT _expected STREQUAL _commit)
            message(FATAL_ERROR
                "Inconsistent ${NAME} dependency:\n${_details}")
        endif()
    endforeach()

    string(MAKE_C_IDENTIFIER "${NAME}_${_expected}" _report_key)
    get_property(_already_reported GLOBAL PROPERTY
        "ARIADNE_DEPENDENCY_REPORT_${_report_key}")
    if(NOT _already_reported)
        message(STATUS "Verified ${NAME} dependency commit: ${_expected}")
        set_property(GLOBAL PROPERTY
            "ARIADNE_DEPENDENCY_REPORT_${_report_key}" TRUE)
    endif()
endfunction()
