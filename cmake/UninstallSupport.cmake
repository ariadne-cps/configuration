include_guard(GLOBAL)

function(setup_project_uninstall)
    if(TARGET uninstall)
        return()
    endif()

    configure_file(
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/Uninstall.cmake.in"
        "${PROJECT_BINARY_DIR}/Uninstall.cmake"
        @ONLY
    )

    add_custom_target(uninstall
        COMMAND "${CMAKE_COMMAND}" -P "${PROJECT_BINARY_DIR}/Uninstall.cmake"
        COMMENT "Uninstalling files listed in install_manifest.txt"
    )
endfunction()
