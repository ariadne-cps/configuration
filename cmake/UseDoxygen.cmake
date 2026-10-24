# Shared standalone C++ documentation support for Ariadne repositories.
include_guard(GLOBAL)
include(CMakeParseArguments)

function(ariadne_setup_documentation)
  if(NOT CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)
    return()
  endif()
  set(options)
  set(oneValueArgs)
  set(multiValueArgs INPUT IMAGE_PATH)
  cmake_parse_arguments(DOC "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
  find_package(Doxygen QUIET)
  if(NOT DOXYGEN_FOUND)
    message(STATUS "Doxygen not found: doc targets are disabled")
    return()
  endif()

  get_filename_component(_configuration_root "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/.." ABSOLUTE)
  set(DOXYFILE_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/docs" CACHE PATH "Doxygen output directory")
  option(DOXYFILE_LATEX "Generate LaTeX sources for PDF documentation" ON)
  if(DOXYFILE_LATEX)
    set(DOXYFILE_GENERATE_LATEX YES)
  else()
    set(DOXYFILE_GENERATE_LATEX NO)
  endif()
  if(NOT DOC_INPUT)
    set(DOC_INPUT "${PROJECT_SOURCE_DIR}/include" "${PROJECT_SOURCE_DIR}/src")
  endif()
  foreach(_source IN LISTS DOC_INPUT)
    if(NOT EXISTS "${_source}")
      message(FATAL_ERROR "Documentation input does not exist: ${_source}")
    endif()
  endforeach()
  set(DOXYFILE_INPUT "")
  foreach(_source IN LISTS DOC_INPUT)
    string(APPEND DOXYFILE_INPUT " \"${_source}\"")
  endforeach()
  set(DOXYFILE_IMAGE_PATH "")
  foreach(_source IN LISTS DOC_IMAGE_PATH)
    if(EXISTS "${_source}")
      string(APPEND DOXYFILE_IMAGE_PATH " \"${_source}\"")
    endif()
  endforeach()

  set(_doxyfile "${CMAKE_CURRENT_BINARY_DIR}/Doxyfile")
  configure_file("${_configuration_root}/doc/Doxyfile.in" "${_doxyfile}" @ONLY)
  add_custom_target(doxygen
    COMMAND "${DOXYGEN_EXECUTABLE}" "${_doxyfile}"
    WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
    COMMENT "Building Doxygen documentation for ${PROJECT_NAME}"
    VERBATIM)
  add_custom_target(doc DEPENDS doxygen)
  add_custom_target(doc-html DEPENDS doxygen)

  find_package(Python3 COMPONENTS Interpreter QUIET)
  if(Python3_Interpreter_FOUND)
    add_custom_target(doc-markdown
      COMMAND "${Python3_EXECUTABLE}" "${_configuration_root}/scripts/build_doc_markdown.py"
        --xml "${DOXYFILE_OUTPUT_DIR}/xml" --output "${DOXYFILE_OUTPUT_DIR}/markdown"
      DEPENDS doxygen
      COMMENT "Converting Doxygen XML to public API Markdown"
      VERBATIM)
  endif()

  if(DOXYFILE_LATEX)
    find_program(_doc_make make)
    find_program(_doc_pdflatex pdflatex)
    if(_doc_make AND _doc_pdflatex)
      add_custom_target(doc-pdf
        COMMAND "${_doc_make}"
        WORKING_DIRECTORY "${DOXYFILE_OUTPUT_DIR}/latex"
        DEPENDS doxygen
        COMMENT "Compiling Doxygen PDF"
        VERBATIM)
    endif()
  endif()
endfunction()
