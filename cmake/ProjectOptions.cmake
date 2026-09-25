include_guard(GLOBAL)

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
