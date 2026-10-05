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

    if(NOT CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        return()
    endif()

    add_library(${PROJECT_LIBRARY_TARGET} ${LIBRARY_KIND})

    foreach(_object_target IN LISTS PROJECT_LIBRARY_OBJECTS)
        if(NOT TARGET ${_object_target})
            message(FATAL_ERROR
                "Object target '${_object_target}' does not exist.")
        endif()
        target_sources(${PROJECT_LIBRARY_TARGET} PRIVATE
            $<TARGET_OBJECTS:${_object_target}>)
    endforeach()

    if(PROJECT_LIBRARY_LINK_LIBRARIES)
        target_link_libraries(${PROJECT_LIBRARY_TARGET}
            PUBLIC ${PROJECT_LIBRARY_LINK_LIBRARIES})
    endif()

    set_property(GLOBAL PROPERTY
        ARIADNE_PROJECT_LIBRARY_TARGET
        ${PROJECT_LIBRARY_TARGET})

    install(TARGETS ${PROJECT_LIBRARY_TARGET}
        LIBRARY DESTINATION lib
        ARCHIVE DESTINATION lib
        RUNTIME DESTINATION bin
    )
endfunction()
