include_guard(GLOBAL)

include(CMakeParseArguments)

function(ariadne_add_python_module)
    set(_options)
    set(_one_value_args NAME MODULE_SOURCE)
    set(_multi_value_args
        PRIVATE_INCLUDE_DIRECTORIES
        PRIVATE_LINK_LIBRARIES
        PRIVATE_COMPILE_DEFINITIONS
        PRIVATE_COMPILE_OPTIONS
    )
    cmake_parse_arguments(
        ARIADNE_PY
        "${_options}"
        "${_one_value_args}"
        "${_multi_value_args}"
        ${ARGN}
    )

    if(NOT ARIADNE_PY_NAME)
        message(FATAL_ERROR "ariadne_add_python_module requires NAME")
    endif()
    if(NOT ARIADNE_PY_MODULE_SOURCE)
        message(FATAL_ERROR "ariadne_add_python_module requires MODULE_SOURCE")
    endif()

    set(_interface_target "pyariadne-${ARIADNE_PY_NAME}")
    set(_module_object_target "${_interface_target}-module-obj")
    set(_entry_object_target "${_interface_target}-entry-obj")

    if(NOT TARGET ${_interface_target})
        message(FATAL_ERROR
            "ariadne_add_python_module requires existing target ${_interface_target}")
    endif()

    get_target_property(_python_common_source_dir
        pyariadne-python-common SOURCE_DIR)

    add_library(${_module_object_target} OBJECT
        "${ARIADNE_PY_MODULE_SOURCE}"
    )
    target_include_directories(${_module_object_target} PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${_python_common_source_dir}/include"
        ${ARIADNE_PY_PRIVATE_INCLUDE_DIRECTORIES}
    )
    target_link_libraries(${_module_object_target} PRIVATE
        pyariadne-python-common
        pybind11::module
        ${ARIADNE_PY_PRIVATE_LINK_LIBRARIES}
    )
    if(ARIADNE_PY_PRIVATE_COMPILE_DEFINITIONS)
        target_compile_definitions(${_module_object_target} PRIVATE
            ${ARIADNE_PY_PRIVATE_COMPILE_DEFINITIONS})
    endif()
    if(ARIADNE_PY_PRIVATE_COMPILE_OPTIONS)
        target_compile_options(${_module_object_target} PRIVATE
            ${ARIADNE_PY_PRIVATE_COMPILE_OPTIONS})
    endif()
    set_target_properties(${_module_object_target}
        PROPERTIES POSITION_INDEPENDENT_CODE ON)

    target_sources(${_interface_target} INTERFACE
        $<TARGET_OBJECTS:${_module_object_target}>
    )

    get_property(_registered_modules GLOBAL PROPERTY ARIADNE_PYTHON_MODULES)
    if(NOT _registered_modules)
        set(_registered_modules)
    endif()
    list(FIND _registered_modules "${ARIADNE_PY_NAME}" _module_index)
    if(_module_index EQUAL -1)
        set_property(GLOBAL APPEND PROPERTY
            ARIADNE_PYTHON_MODULES "${ARIADNE_PY_NAME}")
    endif()

    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        get_property(_registered_modules GLOBAL PROPERTY ARIADNE_PYTHON_MODULES)

        set(_entry_content "#include \"pybind11.hpp\"\n\n")
        foreach(_module IN LISTS _registered_modules)
            string(APPEND _entry_content
                "void ${_module}_module(pybind11::module& module);\n")
        endforeach()

        string(APPEND _entry_content
            "\nPYBIND11_MODULE(pyariadne, module) {\n")
        foreach(_module IN LISTS _registered_modules)
            string(APPEND _entry_content
                "    ${_module}_module(module);\n")
        endforeach()
        string(APPEND _entry_content "}\n")

        set(_entry_source
            "${CMAKE_CURRENT_BINARY_DIR}/${ARIADNE_PY_NAME}_python_entry.cpp")
        file(GENERATE
            OUTPUT "${_entry_source}"
            CONTENT "${_entry_content}"
        )

        add_library(${_entry_object_target} OBJECT
            "${_entry_source}"
        )
        target_include_directories(${_entry_object_target} PRIVATE
            "${_python_common_source_dir}/include"
        )
        target_link_libraries(${_entry_object_target} PRIVATE
            pyariadne-python-common
            pybind11::module
        )
        set_target_properties(${_entry_object_target}
            PROPERTIES POSITION_INDEPENDENT_CODE ON)
    endif()
endfunction()


function(ariadne_finalize_python_module)
    set(_options)
    set(_one_value_args NAME)
    cmake_parse_arguments(
        ARIADNE_PY
        "${_options}"
        "${_one_value_args}"
        ""
        ${ARGN}
    )

    if(NOT ARIADNE_PY_NAME)
        message(FATAL_ERROR "ariadne_finalize_python_module requires NAME")
    endif()

    set(_module_target "${ARIADNE_PY_NAME}")
    set(_interface_target "pyariadne-${ARIADNE_PY_NAME}")
    set(_entry_object_target "${_interface_target}-entry-obj")

    if(NOT TARGET ${_module_target})
        message(FATAL_ERROR
            "ariadne_finalize_python_module requires existing target ${_module_target}")
    endif()
    if(NOT TARGET ${_interface_target})
        message(FATAL_ERROR
            "ariadne_finalize_python_module requires existing target ${_interface_target}")
    endif()
    if(NOT TARGET ${_entry_object_target})
        message(FATAL_ERROR
            "ariadne_finalize_python_module requires existing target ${_entry_object_target}")
    endif()

    get_target_property(_object_targets
        ${_module_target} ARIADNE_PROJECT_OBJECT_TARGETS)
    if(NOT _object_targets)
        message(FATAL_ERROR
            "Target ${_module_target} has no ARIADNE_PROJECT_OBJECT_TARGETS")
    endif()

    pybind11_add_module(pyariadne
        $<TARGET_OBJECTS:${_entry_object_target}>
    )
    foreach(_object_target IN LISTS _object_targets)
        target_sources(pyariadne PRIVATE
            $<TARGET_OBJECTS:${_object_target}>
        )
    endforeach()
    target_link_libraries(pyariadne PRIVATE
        ${_interface_target}
        ${_module_target}
    )
endfunction()
