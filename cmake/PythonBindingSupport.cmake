include_guard(GLOBAL)

include(CMakeParseArguments)

function(ariadne_add_python_bindings)
    set(_options)
    set(_one_value_args NAME MODULE_SOURCE)
    set(_multi_value_args
        SUBMODULE_SOURCES
        PRIVATE_INCLUDE_DIRECTORIES
        INTERFACE_INCLUDE_DIRECTORIES
        PRIVATE_LINK_LIBRARIES
        INTERFACE_LINK_LIBRARIES
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
        message(FATAL_ERROR "ariadne_add_python_bindings requires NAME")
    endif()
    if(NOT ARIADNE_PY_MODULE_SOURCE)
        message(FATAL_ERROR "ariadne_add_python_bindings requires MODULE_SOURCE")
    endif()

    set(_interface_target "pyariadne-${ARIADNE_PY_NAME}")
    set(_object_target "${_interface_target}-submodule-obj")
    set(_module_object_target "${_interface_target}-module-obj")

    get_target_property(_python_common_source_dir
        pyariadne-python-common SOURCE_DIR)

    add_library(${_object_target} OBJECT
        ${ARIADNE_PY_MODULE_SOURCE}
        ${ARIADNE_PY_SUBMODULE_SOURCES}
    )
    target_include_directories(${_object_target} PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${_python_common_source_dir}/include"
        ${ARIADNE_PY_PRIVATE_INCLUDE_DIRECTORIES}
    )
    target_link_libraries(${_object_target} PRIVATE
        pyariadne-python-common
        pybind11::module
        ${ARIADNE_PY_PRIVATE_LINK_LIBRARIES}
    )
    if(ARIADNE_PY_PRIVATE_COMPILE_DEFINITIONS)
        target_compile_definitions(${_object_target} PRIVATE
            ${ARIADNE_PY_PRIVATE_COMPILE_DEFINITIONS})
    endif()
    if(ARIADNE_PY_PRIVATE_COMPILE_OPTIONS)
        target_compile_options(${_object_target} PRIVATE
            ${ARIADNE_PY_PRIVATE_COMPILE_OPTIONS})
    endif()
    set_target_properties(${_object_target}
        PROPERTIES POSITION_INDEPENDENT_CODE ON)

    add_library(${_interface_target} INTERFACE)
    target_sources(${_interface_target} INTERFACE
        $<TARGET_OBJECTS:${_object_target}>
    )
    target_include_directories(${_interface_target} INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
        ${ARIADNE_PY_INTERFACE_INCLUDE_DIRECTORIES}
    )
    target_link_libraries(${_interface_target} INTERFACE
        ${ARIADNE_PY_INTERFACE_LINK_LIBRARIES}
    )

    if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
        set(_entry_source
            "${CMAKE_CURRENT_BINARY_DIR}/${ARIADNE_PY_NAME}_python_entry.cpp")
        file(GENERATE
            OUTPUT "${_entry_source}"
            CONTENT
"#include \"pybind11.hpp\"\n\nvoid ${ARIADNE_PY_NAME}_module(pybind11::module& module);\n\nPYBIND11_MODULE(pyariadne, module) {\n    ${ARIADNE_PY_NAME}_module(module);\n}\n"
        )

        add_library(${_module_object_target} OBJECT
            "${_entry_source}"
        )
        target_include_directories(${_module_object_target} PRIVATE
            "${_python_common_source_dir}/include"
        )
        target_link_libraries(${_module_object_target} PRIVATE
            pyariadne-python-common
            pybind11::module
        )
        set_target_properties(${_module_object_target}
            PROPERTIES POSITION_INDEPENDENT_CODE ON)
    endif()
endfunction()
