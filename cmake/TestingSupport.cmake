include_guard(GLOBAL)

# Called by standalone test configuration. An existing Testing target is reused;
# otherwise, a declared Testing submodule is initialized from its pinned gitlink.
# Projects without that submodule keep their independent CTest infrastructure.
# Never link Testing to production modules or create installation rules.
macro(ariadne_setup_testing)
    if(NOT TARGET ariadne-testing)
        _ariadne_resolve_submodule_path(
            "${PROJECT_SOURCE_DIR}" "testing" _ariadne_testing_path OPTIONAL)
        if(NOT _ariadne_testing_path STREQUAL "")
            ariadne_add_submodule(testing)
        endif()
    endif()
    if(TARGET ariadne-testing AND NOT TARGET testing)
        message(FATAL_ERROR
            "Ariadne Testing target exists without its 'testing' interface target.")
    endif()
endmacro()
