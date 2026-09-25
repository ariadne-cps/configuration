include_guard(GLOBAL)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")

include(CMakeParseArguments)
include(CoverageSupport)
include(DependencyChecks)

function(enable_project_options)
    set(CMAKE_MACOSX_RPATH 1 PARENT_SCOPE)
    set(BUILD_SHARED_LIBS ON PARENT_SCOPE)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON PARENT_SCOPE)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin" PARENT_SCOPE)
    set(CMAKE_CXX_STANDARD 20 PARENT_SCOPE)
    set(CMAKE_CXX_STANDARD_REQUIRED ON PARENT_SCOPE)

    if(NOT WIN32)
        set(_warnings
            all
            extra
            pedantic
            sign-conversion
            cast-qual
            disabled-optimization
            init-self
            missing-include-dirs
            sign-promo
            switch-default
            undef
            redundant-decls
            strict-aliasing
            unused-parameter
            shadow
            error
        )
        foreach(_warning IN LISTS _warnings)
            add_compile_options(-W${_warning})
        endforeach()
    else()
        add_compile_options(/WX)
    endif()
endfunction()

function(check_project_compiler)
    if(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
        if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 19.20)
            message(FATAL_ERROR "MSVC version must be at least 19.20!")
        endif()
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
        if(NOT EXISTS "/etc/nv_tegra_release")
            if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 10.2)
                message(FATAL_ERROR "GCC version must be at least 10.2!")
            endif()
        endif()
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "AppleClang|Clang")
        if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 11.0)
            message(FATAL_ERROR "Clang version must be at least 11.0!")
        endif()
    else()
        message(WARNING "You are using an unsupported compiler! MSVC, GCC and Clang are supported.")
    endif()
endfunction()

macro(configure_library_kind)
    if(WIN32)
        set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS TRUE)
    endif()
    set(LIBRARY_KIND SHARED)
endmacro()

macro(setup_project)
    option(COVERAGE "Enable coverage reporting" OFF)

    enable_project_options()
    enable_project_coverage()
    check_project_compiler()
    configure_library_kind()
endmacro()
