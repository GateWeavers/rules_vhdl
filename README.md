# gateweaver_rules_vhdl

Modern, hermetic, and automated VHDL simulation rules for [Bazel](https://bazel.build).

`gateweaver_rules_vhdl` provides a robust infrastructure for VHDL development, integrating standard simulators (GHDL, NVC) with the [VUnit](https://vunit.github.io/) verification framework. It leverages `aspect_rules_py` for a fully hermetic Python environment and includes a custom Gazelle extension for automated `BUILD.bazel` generation.

## Key Features

- **Hermetic Toolchains**: Automatic fetching and isolation of simulators (GHDL/NVC). No manual installation required.
- **VUnit Integration**: Native support for VUnit testbenches and custom Python runners.
- **Automated Build Generation**: Custom Gazelle extension that scans VHDL source code to generate and update Bazel rules automatically.
- **Bzlmod Ready**: Modern Bazel dependency management out of the box.
- **Advanced Python Support**: Easily add custom Python libraries (like `crc`, `numpy`) to your simulation environment.

---

## Installation

Add the following to your `MODULE.bazel` file:

```starlark
bazel_dep(name = "gateweaver_rules_vhdl", version = "0.1.0")

# Register VHDL Toolchains (Hermetic Simulators)
vhdl_toolchains = use_extension("@gateweaver_rules_vhdl//simulator:extensions.bzl", "vhdl_toolchains")

# Define a GHDL toolchain (mcode backend)
vhdl_toolchains.ghdl(
    name = "ghdl_mcode",
    version = "6.0",
    backend = "mcode",
    url = "https://github.com/ghdl/ghdl/releases/download/v6.0.0/ghdl-mcode-6.0.0-ubuntu24.04-x86_64.tar.gz",
    sha256 = "30d6a977b8456d140bbafecbbe64b1947a3d92eeae8f5e6d9f528a174f9566e7",
    strip_prefix = "ghdl-mcode-6.0.0-ubuntu24.04-x86_64",
    is_default = True,
)

use_repo(vhdl_toolchains, "vhdl_toolchains")
register_toolchains("@vhdl_toolchains//:all")
```

### Opt-in for VUnit Support

If you want to use `vunit_sim`, you must also configure a hermetic Python environment in your `MODULE.bazel`. You can reuse the versions and lockfile provided by the ruleset for a zero-configuration experience:

```starlark
bazel_dep(name = "aspect_rules_py", version = "1.11.5")

# 1. Configure Python Interpreter
interpreters = use_extension("@aspect_rules_py//py/unstable:extension.bzl", "python_interpreters")
interpreters.toolchain(python_version = "3.12", is_default = True)
use_repo(interpreters, "python_interpreters")
register_toolchains("@python_interpreters//:all")

# 2. Configure UV toolchain
uv_bin = use_extension("@aspect_rules_py//uv/unstable:extension.bzl", "uv_bin")
uv_bin.toolchain(version = "0.11.6")
use_repo(uv_bin, "uv")
register_toolchains("@uv//:all")

# 3. Define the hub linking to ruleset's lockfile
uv = use_extension("@aspect_rules_py//uv/unstable:extension.bzl", "uv")
uv.declare_hub(hub_name = "pypi")
uv.project(
    hub_name = "pypi",
    lock = "@gateweaver_rules_vhdl//:uv.lock",
    pyproject = "@gateweaver_rules_vhdl//:pyproject.toml",
)
use_repo(uv, "pypi")
```

---

## Usage

### 1. Defining a Library

```starlark
load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "vhdl_library")

vhdl_library(
    name = "uart_lib",
    srcs = [
        "src/uart_rx.vhd",
        "src/uart_tx.vhd",
    ],
    library_name = "uart_lib",
)
```

### 2. Basic Simulation (`vhdl_test`)

Use `vhdl_test` for standard VHDL testbenches that don't require the VUnit framework.

```starlark
load("@gateweaver_rules_vhdl//sim:sim.bzl", "vhdl_test")

vhdl_test(
    name = "tb_basic",
    srcs = ["test/tb_simple.vhd"],
    dut = ":uart_lib",
    testbench_entity = "tb_simple",
    tool_simulator = "ghdl", # Optional: defaults to the 'is_default' toolchain
)
```

### 3. Running a VUnit Simulation

```starlark
load("@gateweaver_rules_vhdl//sim:vunit_rules.bzl", "vunit_sim")

vunit_sim(
    name = "tb_uart",
    srcs = ["test/tb_uart_rx.vhd"],
    dut = ":uart_lib",
)
```

Run the test:
```bash
bazel test //path/to:tb_uart
```

To run with a GUI (GTKWave), use:
```bash
bazel run //path/to:tb_uart -- --gui
```

### 3. Custom Python Dependencies

If your simulation runner needs extra Python libraries (e.g., `crc`), follow these steps:

**1. Update `pyproject.toml`**
```toml
[project]
name = "my_design"
dependencies = [
    "vunit-hdl==5.0.0-dev.10",
    "crc", # Your extra dependency
]
```

**2. Configure `MODULE.bazel`**
```starlark
uv = use_extension("@aspect_rules_py//uv/unstable:extension.bzl", "uv")
uv.declare_hub(hub_name = "pypi")
uv.project(
    hub_name = "pypi",
    pyproject = "//:pyproject.toml",
    lock = "//:uv.lock", # Optional but recommended
)
use_repo(uv, "pypi")
```

**3. Update `.bazelrc`**
Inform Bazel which venv to use by default:
```text
common --@pypi//venv=my_design
```

**4. Use in `vunit_sim`**
```starlark
vunit_sim(
    name = "tb_with_crc",
    srcs = ["vhdl/tb.vhd"],
    dut = ":lib",
    main = "custom_runner.py",
    deps = ["@pypi//crc"],
)
```

---

## Automation with Gazelle (Experimental)

`gateweaver_rules_vhdl` includes a Gazelle extension that automates the creation of `vhdl_library` and `vunit_sim` rules.

### Setup

In your root `BUILD.bazel`:

```starlark
load("@gazelle//:def.bzl", "gazelle", "gazelle_binary")

gazelle_binary(
    name = "gazelle_vhdl_binary",
    languages = [
        "@gazelle//language/go",
        "@gateweaver_rules_vhdl//tooling/gazelle/vhdl",
    ],
)

gazelle(
    name = "gazelle",
    gazelle = ":gazelle_vhdl_binary",
)
```
In your root `MODULE.bazel`:

```starlark

```

### Execution

Simply run:
```bash
bazel run //:gazelle
```
The extension will scan your `.vhd` files, identify entities/testbenches, and update your `BUILD` files with the correct dependencies.

### Directives

- `# gazelle:vhdl_enabled false`: Disable VHDL scanning for a specific directory.
- `# gazelle:vhdl_library_name custom_name`: Override the default VHDL library name for a directory.

---

## Examples & Use Cases

The following examples demonstrate common patterns. You can find complete code for these in the `e2e/` directory.

### 1. Minimal (Standard VHDL Test)
Ideal for simple designs not requiring VUnit.
- **Rules**: `vhdl_library`, `vhdl_test`.
- **Location**: `e2e/minimal_example`

```starlark
vhdl_library(
    name = "lib",
    srcs = ["vhdl/lib.vhd"],
    library_name = "work",
)

vhdl_test(
    name = "tb_ghdl",
    srcs = ["vhdl/tb.vhd"],
    dut = ":lib",
    testbench_entity = "tb",
)
```

### 2. VUnit with Custom Runner
Demonstrates co-simulation with custom Python logic.
- **Rules**: `vunit_sim`.
- **Location**: `e2e/simple_example`

```python
vunit_sim(
    name = "tb_vunit_custom",
    srcs = ["vhdl/tb.vhd"],
    dut = ":lib",
    main = "custom_runner.py", # Custom Python runner
)
```

### 3. VUnit with External Python Deps
Use libraries like `crc`, `numpy`, or `scipy` in your testbench.
- **Location**: `e2e/custom_py_deps`

```python
vunit_sim(
    name = "tb_custom_deps",
    srcs = ["vhdl/tb.vhd"],
    dut = ":lib",
    main = "custom_runner.py",
    deps = ["@pypi//crc"], # External Python library
)
```

---

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.
