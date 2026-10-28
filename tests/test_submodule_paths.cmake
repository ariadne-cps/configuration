# Run with: cmake -P tests/test_submodule_paths.cmake
cmake_minimum_required(VERSION 3.15)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/DependencyChecks.cmake")
set(_fixture "${CMAKE_CURRENT_BINARY_DIR}/ariadne-submodule-path-test")
file(MAKE_DIRECTORY "${_fixture}")
file(WRITE "${_fixture}/.gitmodules"
    "[submodule \"cfg\"]\n"
    "  path = ss/cfg\n"
    "  url = https://github.com/ariadne-cps/configuration\n"
    "[submodule \"ss/mac\"]\n"
    "  path = ss/mac\n"
    "  url = https://github.com/ariadne-cps/macro.git\n"
    "[submodule \"legacy-utility\"]\n"
    "  path = ss/utility\n"
    "  url = https://github.com/ariadne-cps/utility\n"
)
foreach(_case IN ITEMS "configuration|ss/cfg" "macro|ss/mac" "utility|ss/utility")
    string(REPLACE "|" ";" _parts "${_case}")
    list(GET _parts 0 _name)
    list(GET _parts 1 _expected)
    _ariadne_resolve_submodule_path("${_fixture}" "${_name}" _actual)
    if(NOT _actual STREQUAL _expected)
        message(FATAL_ERROR "Expected ${_name} => ${_expected}; got ${_actual}")
    endif()
endforeach()
file(REMOVE_RECURSE "${_fixture}")
message(STATUS "Short and legacy submodule resolution passed")
