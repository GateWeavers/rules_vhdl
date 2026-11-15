# VHDL Dependency Graph Example

This example demonstrates how to use the `vhdl_graph` rule from `@rules_vhdl//vhdl:defs.bzl` (or `//vhdl:graph.bzl`) to inspect and visualize VHDL dependency graphs.

## Targets

- `:design_graph`: Generates `<name>.dot` and `<name>.txt` representing the module and library dependency hierarchy.
- `:design_graph_with_files`: Generates the dependency graph including all source (`·`) and data (`◆`) files (`include_files = True`).

## Building the Graph

To generate the graph files:

```bash
bazel build //examples/graph:design_graph
bazel build //examples/graph:design_graph_with_files
```

Bazel writes two output files per target:
- `bazel-bin/examples/graph/<target_name>.txt`: An indented ASCII tree representation.
- `bazel-bin/examples/graph/<target_name>.dot`: A Graphviz DOT file.

## Inspecting the Output

### View the ASCII Tree

```bash
cat bazel-bin/examples/graph/design_graph.txt
cat bazel-bin/examples/graph/design_graph_with_files.txt
```

### Render Graphviz DOT to SVG or PNG

If you have Graphviz installed (`dot`):

```bash
dot -Tsvg bazel-bin/examples/graph/design_graph.dot -o design_graph.svg
dot -Tpng bazel-bin/examples/graph/design_graph_with_files.dot -o design_graph_with_files.png
```
