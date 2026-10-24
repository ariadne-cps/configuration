# Ariadne Configuration

Shared **CMake build infrastructure** for the Ariadne C++ repository family.
Use this repository as a pinned Git submodule; it provides reusable build
functions and targets, not a C++ runtime library.

## Modules and functions

| Module | Functions or macros | Purpose |
| --- | --- | --- |
| `ProjectOptions.cmake` | `setup_project`, `enable_project_options`, `check_project_compiler`, `configure_library_kind`, `report_python_configuration_once` | C++20 compiler options, warnings, shared/static library choices, common project targets and sanitizers. |
| `DependencyChecks.cmake` | `ensure_submodule_initialized`, `get_gitlink_commit`, `require_same_dependency_commit` | Resolve submodule paths and validate pinned dependency consistency along different repository chains. |
| `ProjectLibrarySupport.cmake` | `setup_project_library` | Build the standalone library target from object targets and module dependencies. |
| `InstallBundleSupport.cmake` | `ariadne_register_public_headers`, `ariadne_install_dependency_bundle` | Register and install public header bundles, including reachable project dependencies. |
| `CoverageSupport.cmake` | `enable_project_coverage`, `setup_project_coverage`, `setup_project_tests`, `setup_standalone_project_tests`, `setup_project_benchmarks` | Standalone test/benchmark setup and code coverage, using GCC/lcov or LLVM tools. |
| `PythonBindingSupport.cmake` | `ariadne_add_python_module`, `ariadne_finalize_python_module` | Configure and finalize Python binding modules. |
| `UninstallSupport.cmake` | `setup_project_uninstall` | Create a project uninstall target. |
| `UseDoxygen.cmake` | `ariadne_setup_documentation` | Define `doc`, `doxygen`, `doc-html`, `doc-markdown`, and optionally `doc-pdf`. |

The `GCCCodeCoverage.cmake` and `LLVMCodeCoverage.cmake` modules provide
compiler-specific coverage implementations; `Uninstall.cmake.in` is the
template used for uninstalling a project.

## CMake use

Projects normally include `cmake/ProjectOptions.cmake` via their
`ss/configuration` gitlink and call `setup_project()`.

For standalone API documentation, after the project targets have been set up:

```cmake
include("${PROJECT_SOURCE_DIR}/ss/configuration/cmake/UseDoxygen.cmake")
ariadne_setup_documentation(
  INPUT "${PROJECT_SOURCE_DIR}/include" "${PROJECT_SOURCE_DIR}/src"
)
```

Documentation input paths are supplied by the caller; this repository owns
the Doxygen configuration template and XML-to-Markdown conversion machinery.

```sh
npm install --global moxygen@2.1.19
cmake -S . -B build-docs -DDOXYFILE_LATEX=OFF
cmake --build build-docs --target doc-markdown
```

Doxygen and Python 3 are required for `doc-markdown`; Moxygen 2.1.19 requires
Node.js. Doxygen produces HTML and XML under `build-docs/docs/`, and the
converter produces Markdown under `build-docs/docs/markdown/`. The generated
Markdown excludes private and protected nested compounds from the public
reference while keeping the original Doxygen output unchanged.

The `doc-pdf` target additionally requires a working TeX installation and
`make`. Documentation targets are defined only for standalone projects.
