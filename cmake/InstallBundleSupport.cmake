include_guard(GLOBAL)

include(CMakeParseArguments)

function(ariadne_register_public_headers)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs DIRECTORIES FILES)
    cmake_parse_arguments(ARIADNE_HEADERS
        "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARIADNE_HEADERS_TARGET)
        message(FATAL_ERROR "ariadne_register_public_headers requires TARGET.")
    endif()
    if(NOT TARGET ${ARIADNE_HEADERS_TARGET})
        message(FATAL_ERROR
            "Header owner target '${ARIADNE_HEADERS_TARGET}' does not exist.")
    endif()

    set_property(TARGET ${ARIADNE_HEADERS_TARGET}
        PROPERTY ARIADNE_PUBLIC_HEADERS_REGISTERED TRUE)

    if(ARIADNE_HEADERS_DIRECTORIES)
        set_property(TARGET ${ARIADNE_HEADERS_TARGET}
            APPEND PROPERTY ARIADNE_PUBLIC_HEADER_DIRECTORIES
            ${ARIADNE_HEADERS_DIRECTORIES})
    endif()

    if(ARIADNE_HEADERS_FILES)
        set_property(TARGET ${ARIADNE_HEADERS_TARGET}
            APPEND PROPERTY ARIADNE_PUBLIC_HEADER_FILES
            ${ARIADNE_HEADERS_FILES})
    endif()
endfunction()

function(_ariadne_collect_public_headers TARGET_NAME OUT_DIRECTORIES OUT_FILES OUT_TARGETS)
    set(_queue ${TARGET_NAME})
    set(_visited)
    set(_directories)
    set(_files)
    set(_targets)

    while(_queue)
        list(POP_FRONT _queue _current)

        if(_current IN_LIST _visited)
            continue()
        endif()
        list(APPEND _visited "${_current}")

        if(NOT TARGET ${_current})
            continue()
        endif()

        get_target_property(_registered ${_current} ARIADNE_PUBLIC_HEADERS_REGISTERED)
        if(NOT _registered)
            continue()
        endif()

        list(APPEND _targets "${_current}")

        get_target_property(_current_directories ${_current} ARIADNE_PUBLIC_HEADER_DIRECTORIES)
        if(_current_directories AND NOT _current_directories STREQUAL "_current_directories-NOTFOUND")
            list(APPEND _directories ${_current_directories})
        endif()

        get_target_property(_current_files ${_current} ARIADNE_PUBLIC_HEADER_FILES)
        if(_current_files AND NOT _current_files STREQUAL "_current_files-NOTFOUND")
            list(APPEND _files ${_current_files})
        endif()

        get_target_property(_dependencies ${_current} INTERFACE_LINK_LIBRARIES)
        if(_dependencies AND NOT _dependencies STREQUAL "_dependencies-NOTFOUND")
            foreach(_dependency IN LISTS _dependencies)
                if(TARGET ${_dependency})
                    get_target_property(_dependency_registered
                        ${_dependency} ARIADNE_PUBLIC_HEADERS_REGISTERED)
                    if(_dependency_registered)
                        list(APPEND _queue "${_dependency}")
                    endif()
                endif()
            endforeach()
        endif()
    endwhile()

    if(_directories)
        list(REMOVE_DUPLICATES _directories)
    endif()
    if(_files)
        list(REMOVE_DUPLICATES _files)
    endif()
    if(_targets)
        list(REMOVE_DUPLICATES _targets)
    endif()

    set(${OUT_DIRECTORIES} "${_directories}" PARENT_SCOPE)
    set(${OUT_FILES} "${_files}" PARENT_SCOPE)
    set(${OUT_TARGETS} "${_targets}" PARENT_SCOPE)
endfunction()

function(ariadne_install_dependency_bundle)
    set(options)
    set(oneValueArgs TARGET DESTINATION)
    set(multiValueArgs)
    cmake_parse_arguments(ARIADNE_INSTALL
        "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARIADNE_INSTALL_TARGET)
        message(FATAL_ERROR "ariadne_install_dependency_bundle requires TARGET.")
    endif()
    if(NOT ARIADNE_INSTALL_DESTINATION)
        message(FATAL_ERROR "ariadne_install_dependency_bundle requires DESTINATION.")
    endif()

    _ariadne_collect_public_headers(
        ${ARIADNE_INSTALL_TARGET}
        _directories
        _files
        _targets)

    if(NOT _targets)
        message(FATAL_ERROR
            "No registered Ariadne public headers are reachable from target '${ARIADNE_INSTALL_TARGET}'.")
    endif()

    if(_files)
        install(FILES ${_files}
            DESTINATION "${ARIADNE_INSTALL_DESTINATION}")
    endif()

    foreach(_directory IN LISTS _directories)
        install(DIRECTORY "${_directory}"
            DESTINATION "${ARIADNE_INSTALL_DESTINATION}")
    endforeach()
endfunction()
