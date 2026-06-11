# gateweaver_rules_vhdl: Technical Reference

This document provides a comprehensive reference for the Bazel rules and attributes provided by `gateweaver_rules_vhdl`.

## VHDL Core Rules (`@gateweaver_rules_vhdl//vhdl`)

### `vhdl_library`
Aggregates VHDL source files into a named library and manages transitive dependencies.

| Attribute | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `srcs` | `label_list` | `[]` | List of `.vhd` source files. |
| `library_name` | `string` | `"work"` | The VHDL library name these sources belong to. Cannot be `std` or `ieee`. |
| `vhdl_version` | `string` | `"2008"` | VHDL standard: `"87"`, `"93"`, `"2008"`, or `"2019"`. |
| `deps` | `label_list` | `[]` | Dependencies providing `VhdlLibraryInfo`. |
| `merge_work_lib`| `bool` | `False` | If True, merges sources from dependencies assigned to the `"work"` library into this library. |

### `vhdl_module`
Defines a specific VHDL entity, its generics, and its position in the dependency tree.

| Attribute | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `entity_name` | `string` | Mandatory | The name of the VHDL entity. |
| `srcs` | `label_list` | `[]` | Source files for this module. |
| `library_name` | `string` | `"work"` | The library this module belongs to. |
| `generics` | `string_dict`| `{}` | Map of generic names to values (as strings). |
| `deps` | `label_list` | `[]` | Transitive dependencies. |

---

## Simulation Rules (`@gateweaver_rules_vhdl//sim`)

### `vhdl_test`
Runs a standard VHDL testbench using the resolved toolchain.

| Attribute | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `srcs` | `label_list` | Mandatory | Testbench source files. |
| `dut` | `label` | Mandatory | The Design Under Test (`vhdl_library` or `vhdl_module`). |
| `testbench_entity`| `string` | Mandatory | The name of the testbench entity to execute. |
| `vhdl_version` | `string` | `"2008"` | VHDL standard for the testbench. |
| `sim_args` | `string_list`| `[]` | Additional arguments passed to the simulator. |
| `simulator` | `label` | `None` | Optional explicit simulator toolchain label (e.g., `@vhdl_toolchains//:ghdl_6_0_mcode`). |

### `vunit_sim` (Macro)
Runs a VUnit-based simulation. Automatically handles runner generation and configuration.

| Attribute | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | Mandatory | Unique name for the test target. |
| `dut` | `label` | Mandatory | The design under test. |
| `srcs` | `label_list` | `[]` | Testbench source files. |
| `main` | `label` | `None` | Optional custom `run.py` script. |
| `deps` | `label_list` | `[]` | Extra Python dependencies. `@pypi//vunit_hdl` is included implicitly. |
| `simulator` | `label` | `None` | Explicit simulator selection. |

---

## Toolchain Management (`@gateweaver_rules_vhdl//simulator`)

### `vhdl_toolchains` (Module Extension)
Manages hermetic installations of VHDL simulators (GHDL, NVC).

**Tag: `ghdl`**
- `name`: Repository name.
- `version`: Version string.
- `backend`: `"mcode"` or `"llvm"`.
- `url`, `sha256`, `strip_prefix`: Archive details.
- `is_default`: Set as global default simulator.

**Tag: `nvc`**
- `name`, `version`, `url`, `sha256`, `is_default`.

### Registration

To register toolchains, use the `vhdl_toolchains` hub repo. Here is a complete `MODULE.bazel` example:

```python
# Use the toolchain extension
vhdl_toolchains = use_extension("@gateweaver_rules_vhdl//simulator:extensions.bzl", "vhdl_toolchains")

# Define one or more toolchains
vhdl_toolchains.ghdl(
    name = "ghdl_mcode",
    version = "6.0",
    backend = "mcode",
    url = "https://github.com/ghdl/ghdl/releases/download/v6.0.0/ghdl-mcode-6.0.0-ubuntu24.04-x86_64.tar.gz",
    sha256 = "30d6a977b8456d140bbafecbbe64b1947a3d92eeae8f5e6d9f528a174f9566e7",
    strip_prefix = "ghdl-mcode-6.0.0-ubuntu24.04-x86_64",
    is_default = True,
)

# Declare the hub repository
use_repo(vhdl_toolchains, "vhdl_toolchains")

# Register all toolchains defined in the hub
register_toolchains("@vhdl_toolchains//:all")
```

---

## VUnit-Bazel Python API
For custom `main` scripts in `vunit_sim`.

- `get_vunit_from_bazel()`: Initializes the VUnit environment with the correct toolchain and returns a `VUnit` instance.
- `add_lib_from_bazel(vu)`: Populates a `VUnit` instance with the libraries and sources defined in the Bazel target.

### Custom Runner Example (`run.py`)

When using the `main` attribute in `vunit_sim`, you can author a custom runner to enable advanced VUnit features:

```python
from sim.vunit_bazel_helper import get_vunit_from_bazel, add_lib_from_bazel

def main():
    # 1. Initialize VUnit with Bazel-resolved toolchain
    vu = get_vunit_from_bazel()
    
    # 2. Add standard/support libraries
    vu.add_vhdl_builtins()
    vu.add_osvvm()
    vu.add_verification_components()
    
    # 3. Automatically add all design libraries defined in BUILD.bazel
    add_lib_from_bazel(vu)
    
    # 4. Custom VUnit configuration (optional)
    # vu.set_sim_option("ghdl.elaborate_options", ["--ieee=synopsys"])
    
    # 5. Execute simulation
    vu.main()

if __name__ == "__main__":
    main()
```

---

## Running with GUI (GTKWave)

`gateweaver_rules_vhdl` supports running simulations interactively with a GUI. This is typically used with **GTKWave**.

### 1. Configure the Runner
In your `run.py`, ensure the simulator is configured to use GTKWave as the viewer:

```python
vu = get_vunit_from_bazel()
# ...
vu.set_sim_option("ghdl.viewer", "gtkwave")
```

### 2. Execute with `bazel run`
To open the GUI, you must use `bazel run` (not `test`) and pass the `--gui` flag to the underlying VUnit runner:

```bash
bazel run //path/to:tb_name -- --gui
```

### 3. Debugging with `no-sandbox`
If the GUI fails to open due to X11 restrictions, add the `no-sandbox` tag to your target in `BUILD.bazel`:

```starlark
vunit_sim(
    name = "tb_gui",
    # ...
    tags = ["no-sandbox"],
)

---

## Examples & Use Cases

### Minimal Setup (No VUnit)
**Goal**: Run a simple VHDL testbench without the overhead of VUnit.
**Files**: `e2e/minimal_example`

1.  **Define Library**:
    ```starlark
    vhdl_library(
        name = "lib",
        srcs = ["vhdl/lib.vhd"],
    )
    ```
2.  **Define Test**:
    ```starlark
    vhdl_test(
        name = "tb",
        srcs = ["vhdl/tb.vhd"],
        dut = ":lib",
        testbench_entity = "tb",
    )
    ```

### VUnit with External Python Dependencies
**Goal**: Use a third-party Python library (e.g., `crc`) to verify simulation data.
**Files**: `e2e/custom_py_deps`

1.  **`pyproject.toml`**:
    ```toml
    dependencies = ["vunit-hdl", "crc"]
    ```
2.  **`run.py`**:
    ```python
    from crc import Calculator
    # Use Calculator to check simulation results...
    ```
3.  **`BUILD.bazel`**:
    ```starlark
    vunit_sim(
        name = "tb",
        main = "run.py",
        deps = ["@pypi//crc"],
    )
    ```
```
