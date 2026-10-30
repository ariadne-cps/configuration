include_guard(GLOBAL)

# Called only for projects opting in to USE_ARIADNE_TESTING through
# setup_standalone_project_tests. The dependency is built from source,
# used only by tests and never attached to a production target.
macro(ariadne_setup_testing)
    if(NOT TARGET ariadne-testing)
        ariadne_add_submodule(testing)
    endif()
    if(NOT TARGET ariadne-testing OR NOT TARGET testing)
        message(FATAL_ERROR
            "Ariadne Testing must provide 'ariadne-testing' and 'testing' targets.")
    endif()
endmacro()
