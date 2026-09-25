include_guard(GLOBAL)

include(CMakeParseArguments)

function(enable_project_options)
    set(CMAKE_MACOSX_RPATH 1 PARENT_SCOPE)
    set(BUILD_SHARED_LIBS ON PARENT_SCOPE)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON PARENT_SCOPE)
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
    set(options NO_MSVC ALLOW_TEGRA_GCC APPLE_CLANG_ANY_VERSION)
    set(oneValueArgs MSVC_MIN GCC_MIN CLANG_MIN)
    cmake_parse_arguments(COMPILER "${options}" "${oneValueArgs}" "" ${ARGN})

    if(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
        if(COMPILER_NO_MSVC)
            message(FATAL_ERROR "MSVC is not supported.")
        elseif(COMPILER_MSVC_MIN AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS COMPILER_MSVC_MIN)
            message(FATAL_ERROR "MSVC version must be at least ${COMPILER_MSVC_MIN}!")
        endif()
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
        if(COMPILER_GCC_MIN)
            if(NOT COMPILER_ALLOW_TEGRA_GCC OR NOT EXISTS "/etc/nv_tegra_release")
                if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS COMPILER_GCC_MIN)
                    message(FATAL_ERROR "GCC version must be at least ${COMPILER_GCC_MIN}!")
                endif()
            endif()
        endif()
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "AppleClang")
        if(NOT COMPILER_APPLE_CLANG_ANY_VERSION AND COMPILER_CLANG_MIN
           AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS COMPILER_CLANG_MIN)
            message(FATAL_ERROR "AppleClang version must be at least ${COMPILER_CLANG_MIN}!")
        endif()
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        if(COMPILER_CLANG_MIN AND CMAKE_CXX_COMPILER_VERSION VERSION_LESS COMPILER_CLANG_MIN)
            message(FATAL_ERROR "Clang version must be at least ${COMPILER_CLANG_MIN}!")
        endif()
    else()
        message(WARNING "You are using an unsupported compiler.")
    endif()
endfunction()

macro(configure_library_kind)
    if(WIN32)
        set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS TRUE)
        set(LIBRARY_KIND STATIC)
    elseif(COVERAGE)
        set(LIBRARY_KIND STATIC)
    else()
        set(LIBRARY_KIND SHARED)
    endif()
endmacro()
