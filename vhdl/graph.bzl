#    Copyright 2026 Nocilis
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

"""VHDL dependency graph inspection rules and functions."""

load("//vhdl:providers.bzl", "VhdlLibraryInfo", "VhdlNodeInfo")
load("//vhdl:utils.bzl", "as_infos", "extract_modules", "label_str", "node_of")

_MAX_STEPS = 1000000  # Starlark has no recursion nor `while`: bounded iterative walks.

def _real_deps(node):
    """The labelled nodes among the direct deps of `node`; virtual nodes are looked through."""
    deps = []
    seen = {}
    stack = list(reversed(node.direct_deps))
    for _ in range(_MAX_STEPS):
        if not stack:
            break
        dep = stack.pop()
        if dep.label == None:
            stack.extend(reversed(dep.direct_deps))
        elif dep.label not in seen:
            seen[dep.label] = True
            deps.append(dep)
    if stack:
        fail("The VHDL dependency graph is too large to walk.")
    return deps

def _walk(roots, expand):
    """Post-order walk (dependencies first) over the labelled nodes below `roots`, each once.

    Args:
        roots: list of VhdlNodeInfo.
        expand: dict label -> bool saying whether the deps of a node are
            followed, or None to follow them all.

    Returns:
        (list of nodes, dict label -> list of the nodes it depends on).
    """
    order = []
    deps_of = {}
    seen = {}
    stack = [(node, False) for node in reversed(roots)]
    for _ in range(_MAX_STEPS):
        if not stack:
            break
        node, done = stack.pop()
        if node.label == None:
            stack.extend([(dep, False) for dep in reversed(node.direct_deps)])
            continue
        if done:
            order.append(node)
            continue
        if node.label in seen:
            continue
        seen[node.label] = True
        children = _real_deps(node) if (expand == None or expand[node.label]) else []
        deps_of[node.label] = children
        stack.append((node, True))
        stack.extend([(dep, False) for dep in reversed(children)])
    if stack:
        fail("The VHDL dependency graph is too large to walk.")
    return order, deps_of

def extract_graph(vhdl_info):
    """The dependency graph of Target(s) providing VhdlLibraryInfo, limited to modules.

    Shown: the modules (vhdl_module), the libraries that contain modules (a
    module somewhere below them), and the libraries without any module, only as
    a leaf with their name and version (they are not developed). Virtual nodes
    (accumulations of infos) are looked through.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        struct(nodes, roots). `nodes` is a list in dependency order (dependencies
        first) of structs with the fields:
          label: str, e.g. '//axis:fifo'.
          kind: 'module' or 'library'.
          entity_name: entity of a module, None for a library.
          generics: dict of the generics of a module.
          library_name: library declared by the target.
          library_names: tuple of the libraries a module is compiled into, after
              sealing (several when a default-library module is also sealed
              elsewhere); (library_name,) for a library.
          vhdl_version: VHDL standard.
          srcs: tuple of the short_path of the source files of the target.
          data: tuple of the short_path of the data files of the target.
          deps: tuple of the labels of the direct deps that are shown.
          expanded: False for a library without any module, which is not developed.
        `roots` is the tuple of the labels of the roots.
    """
    infos = as_infos(vhdl_info)
    roots = [node_of(info) for info in infos]

    # The modules, with the library they are compiled into after sealing.
    modules = {}
    for module in extract_modules(infos):
        record = modules.setdefault(label_str(module.label), {"module": module, "libraries": []})
        if module.library_name not in record["libraries"]:
            record["libraries"].append(module.library_name)

    # Which nodes have a module in their closure (dependencies come first).
    everything, all_deps = _walk(roots, None)
    has_modules = {}
    for node in everything:
        has_modules[node.label] = (node.label in modules) or any([has_modules[dep.label] for dep in all_deps[node.label]])

    # The nodes that are shown: libraries without modules are leaves.
    nodes, deps_of = _walk(roots, has_modules)
    shown = []
    for node in nodes:
        record = modules.get(node.label)
        deps = tuple([dep.label for dep in deps_of[node.label]])
        if record:
            module = record["module"]
            shown.append(struct(
                label = node.label,
                kind = "module",
                entity_name = module.entity_name,
                generics = module.generics,
                library_name = node.library_name,
                library_names = tuple(sorted(record["libraries"])),
                vhdl_version = module.vhdl_version,
                srcs = node.srcs,
                data = node.data,
                deps = deps,
                expanded = True,
            ))
        else:
            shown.append(struct(
                label = node.label,
                kind = "library",
                entity_name = None,
                generics = {},
                library_name = node.library_name,
                library_names = (node.library_name,),
                vhdl_version = node.vhdl_version,
                srcs = node.srcs,
                data = node.data,
                deps = deps,
                expanded = has_modules[node.label],
            ))

    virtual_root = VhdlNodeInfo(label = None, library_name = None, vhdl_version = None, direct_deps = tuple(roots), srcs = (), data = ())
    return struct(
        nodes = shown,
        roots = tuple([node.label for node in _real_deps(virtual_root)]),
    )

def _node_text(node):
    if node.kind == "module":
        generics = ""
        if node.generics:
            generics = "(%s)" % ", ".join(["%s=%s" % kv for kv in sorted(node.generics.items())])
        return "module %s%s, lib %s %s" % (node.entity_name, generics, ",".join(node.library_names), node.vhdl_version)
    return "lib %s %s" % (node.library_name, node.vhdl_version)

def graph_tree(vhdl_info, include_files = False):
    """The dependency graph of `extract_graph` as an indented tree (text).

    A node already shown is not developed again: it is marked `(*)`.

    With `include_files`, the files of a node are listed under it, before its
    dependencies: `·` for a source file, `◆` for a data file.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.
        include_files: List the source and data files of each node.

    Returns:
        str, one line per node, ending with a newline.
    """
    graph = extract_graph(vhdl_info)
    by_label = {node.label: node for node in graph.nodes}
    lines = []
    shown = {}

    # (label, prefix of its line, prefix of the lines of its children)
    stack = [(label, "", "") for label in reversed(graph.roots)]
    for _ in range(_MAX_STEPS):
        if not stack:
            break
        label, line_prefix, child_prefix = stack.pop()
        node = by_label[label]
        text = "%s [%s]" % (label, _node_text(node))
        if label in shown and node.deps:
            lines.append(line_prefix + text + " (*)")
            continue
        shown[label] = True
        lines.append(line_prefix + text)
        if include_files:
            # Aligned under the text of the node; the bar keeps the branch to its dependencies.
            file_prefix = child_prefix + ("│   " if node.deps else "    ")
            lines.extend([file_prefix + "· " + path for path in node.srcs])
            lines.extend([file_prefix + "◆ " + path for path in node.data])
        for index in reversed(range(len(node.deps))):
            is_last = index == len(node.deps) - 1
            stack.append((
                node.deps[index],
                child_prefix + ("└── " if is_last else "├── "),
                child_prefix + ("    " if is_last else "│   "),
            ))
    if stack:
        fail("The VHDL dependency graph is too large to walk.")
    return "\n".join(lines) + "\n" if lines else ""

def _dot_escape(text):
    return text.replace("\\", "\\\\").replace("\"", "\\\"")

def graph_dot(vhdl_info, graph_name = "vhdl", include_files = False):
    """The dependency graph of `extract_graph` in DOT, like `bazel query --output graph`.

    An edge `"A" -> "B"` means that A depends on B. Modules are boxes, libraries
    that contain modules are folders, libraries without modules are dashed folders.

    With `include_files`, the files of a node are added to its label, one per
    line: `·` for a source file, `◆` for a data file.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.
        graph_name: Name of the digraph.
        include_files: Add the source and data files of each node to its label.

    Returns:
        str, ending with a newline.
    """
    graph = extract_graph(vhdl_info)
    lines = ["digraph \"%s\" {" % _dot_escape(graph_name), "  node [shape=box];"]
    for node in graph.nodes:
        if node.kind == "module":
            attrs = ""
        elif node.expanded:
            attrs = ", shape=folder"
        else:
            attrs = ", shape=folder, style=dashed"
        text = _dot_escape(node.label) + "\\n" + _dot_escape(_node_text(node))
        if include_files:
            text += "".join(["\\n· " + _dot_escape(path) for path in node.srcs])
            text += "".join(["\\n◆ " + _dot_escape(path) for path in node.data])
        lines.append("  \"%s\" [label=\"%s\"%s]" % (_dot_escape(node.label), text, attrs))
    for node in graph.nodes:
        for dep in node.deps:
            lines.append("  \"%s\" -> \"%s\"" % (_dot_escape(node.label), _dot_escape(dep)))
    lines.append("}")
    return "\n".join(lines) + "\n"

def _vhdl_graph_impl(ctx):
    dot = ctx.actions.declare_file(ctx.label.name + ".dot")
    tree = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(dot, graph_dot(ctx.attr.deps, graph_name = ctx.label.name, include_files = ctx.attr.include_files))
    ctx.actions.write(tree, graph_tree(ctx.attr.deps, include_files = ctx.attr.include_files))
    return [DefaultInfo(files = depset([dot, tree]))]

vhdl_graph = rule(
    implementation = _vhdl_graph_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [VhdlLibraryInfo],
            doc = "Roots of the graph: vhdl_library and vhdl_module targets.",
        ),
        "include_files": attr.bool(
            default = False,
            doc = "List the source and data files of each node (`·` sources, `◆` data).",
        ),
    },
    doc = """Writes the VHDL dependency graph of its deps: <name>.dot and <name>.txt.

    The graph is limited to modules (see `extract_graph`). Render it with
    `bazel build //:graph && dot -Tsvg bazel-bin/graph.dot > graph.svg`.
    """,
)
