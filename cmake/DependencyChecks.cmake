include_guard(GLOBAL)

find_package(Git REQUIRED)

function(get_gitlink_commit REPOSITORY SUBMODULE_PATH OUTPUT_VARIABLE)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${REPOSITORY}" rev-parse "HEAD:${SUBMODULE_PATH}"
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
    set(multiValueArgs REFERENCES)
    cmake_parse_arguments(CHECK "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT CHECK_REFERENCES)
        message(FATAL_ERROR "require_same_dependency_commit(${NAME}) requires REFERENCES.")
    endif()

    set(_expected "")
    set(_details "")
    foreach(_reference IN LISTS CHECK_REFERENCES)
        string(REPLACE "|" ";" _parts "${_reference}")
        list(LENGTH _parts _length)
        if(NOT _length EQUAL 2)
            message(FATAL_ERROR
                "Invalid dependency reference '${_reference}'. Expected REPOSITORY|SUBMODULE_PATH.")
        endif()

        list(GET _parts 0 _repository)
        list(GET _parts 1 _path)
        get_gitlink_commit("${_repository}" "${_path}" _commit)

        string(APPEND _details "  ${_repository}/${_path}: ${_commit}\n")

        if(_expected STREQUAL "")
            set(_expected "${_commit}")
        elseif(NOT _expected STREQUAL _commit)
            message(FATAL_ERROR
                "Inconsistent ${NAME} dependency:\n${_details}")
        endif()
    endforeach()

    message(STATUS "Verified ${NAME} dependency commit: ${_expected}")
endfunction()
