include_guard(GLOBAL)

function(setup_project_library)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs OBJECTS LINK_LIBRARIES)
    cmake_parse_arguments(PROJECT_LIBRARY
        "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT PROJECT_LIBRARY_TARGET)
        message(FATAL_ERROR "setup_project_library requires TARGET.")
    endif()

    list(LENGTH PROJECT_LIBRARY_LINK_LIBRARIES _link_library_count)
    if(NOT _link_library_count EQUAL 1)
        message(FATAL_ERROR
            "setup_project_library requires exactly one LINK_LIBRARIES module target.")
    endif()

    list(GET PROJECT_LIBRARY_LINK_LIBRARIES 0 _module_target)
    if(NOT TARGET ${_module_target})
        message(FATAL_ERROR
            "Project module target '${_module_target}' does not exist.")
    endif()

    set(_object_targets ${PROJECT_LIBRARY_OBJECTS})
    set(_module_targets ${_module_target})
    get_target_property(_interface_dependencies
        ${_module_target} INTERFACE_LINK_LIBRARIES)

    foreach(_dependency IN LISTS _interface_dependencies)
        if(TARGET ${_dependency})
            get_target_property(_dependency_objects
                ${_dependency} ARIADNE_PROJECT_OBJECT_TARGETS)
            if(_dependency_objects)
                list(APPEND _object_targets ${_dependency_objects})
            endif()

            get_target_property(_dependency_modules
                ${_dependency} ARIADNE_PROJECT_MODULE_TARGETS)
            if(_dependency_modules)
                list(APPEND _module_targets ${_dependency_modules})
            endif()
        endif()
    endforeach()

    list(REMOVE_DUPLICATES _object_targets)
    list(REMOVE_DUPLICATES _module_targets)

    foreach(_object_target IN LISTS _object_targets)
        if(NOT TARGET ${_object_target})
            message(FATAL_ERROR
                "Object target '${_object_target}' does not exist.")
        endif()
    endforeach()

    set_property(TARGET ${_module_target} PROPERTY
        ARIADNE_PROJECT_OBJECT_TARGETS ${_object_targets})
    set_property(TARGET ${_module_target} PROPERTY
        ARIADNE_PROJECT_MODULE_TARGETS ${_module_targets})
    set_property(TARGET ${_module_target} PROPERTY
        ARIADNE_PROJECT_SOURCE_ROOT "${PROJECT_SOURCE_DIR}")

    if(NOT CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        return()
    endif()

    add_library(${PROJECT_LIBRARY_TARGET} ${LIBRARY_KIND})

    foreach(_object_target IN LISTS _object_targets)
        target_sources(${PROJECT_LIBRARY_TARGET} PRIVATE
            $<TARGET_OBJECTS:${_object_target}>)
    endforeach()

    target_link_libraries(${PROJECT_LIBRARY_TARGET}
        PUBLIC ${PROJECT_LIBRARY_LINK_LIBRARIES})

    set_property(GLOBAL PROPERTY
        ARIADNE_PROJECT_LIBRARY_TARGET
        ${PROJECT_LIBRARY_TARGET})
    set_property(GLOBAL PROPERTY
        ARIADNE_PROJECT_MODULE_TARGET
        ${_module_target})

    install(TARGETS ${PROJECT_LIBRARY_TARGET}
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        RUNTIME DESTINATION bin
    )
endfunction()
