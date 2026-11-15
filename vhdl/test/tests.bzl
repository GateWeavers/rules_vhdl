#    Copyright 2026 Nocilis

#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at

#        http://www.apache.org/licenses/LICENSE-2.0

#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//vhdl:vhdl.bzl",
    "VhdlLibraryInfo",
    "VhdlModuleInfo",
    "extract_data",
    "extract_graph",
    "extract_modules",
    "extract_sources",
    "extract_srcs",
    "find_module",
    "graph_dot",
    "graph_tree",
    "group_segments",
    "merge_vhdl_library_infos",
    "vhdl_graph",
    "vhdl_library",
    "vhdl_module",
)
load("//vhdl:translation.bzl", "vhdl_translate")

# --- Test 1: Basic Library Creation & Key Generation ---
def _basic_lib_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Check provider existence
    if VhdlLibraryInfo not in target:
        asserts.true(env, False, "VhdlLibraryInfo provider is missing")
        return analysistest.end(env)

    # 2. Check compile-order segment format from extract_sources
    extracted = extract_sources(target)
    asserts.equals(env, 1, len(extracted), "Expected exactly 1 segment")
    segment = extracted[0]
    expected_seg_id = "util_lib@2008#0"
    asserts.equals(env, expected_seg_id, segment.id)
    asserts.equals(env, "util_lib", segment.library_name)
    asserts.equals(env, "2008", segment.vhdl_version)
    asserts.equals(env, 0, segment.index)

    # 3. Check group_segments (lib_name@version)
    grouped = group_segments(extracted)
    libs = {lib.id: lib for lib in grouped}
    expected_key = "util_lib@2008"
    asserts.true(env, expected_key in libs, "Key '{}' not found in libraries".format(expected_key))

    lib_struct = libs[expected_key]
    asserts.equals(env, "util_lib", lib_struct.library_name)
    asserts.equals(env, "2008", lib_struct.vhdl_version)

    # 4. Check extract_srcs helper
    srcs = [f.basename for f in extract_srcs(target).to_list()]
    asserts.true(env, "dummy_util.vhd" in srcs, "dummy_util.vhd missing from extract_srcs")

    # 5. Verify list input aggregation in extract_sources and group_segments
    list_extracted = extract_sources([target, target])
    asserts.equals(env, 1, len(list_extracted), "Expected deduplicated segments for repeated target")
    list_grouped = group_segments(list_extracted)
    list_libs = {lib.id: lib for lib in list_grouped}
    asserts.true(env, expected_key in list_libs, "Key '{}' not found in list-extracted libraries".format(expected_key))

    # 6. Check merge_vhdl_library_infos helper
    merged = merge_vhdl_library_infos([target, target])
    asserts.true(env, merged != None, "merge_vhdl_library_infos returned None")
    merged_srcs = [f.basename for f in extract_srcs(merged).to_list()]
    asserts.true(env, "dummy_util.vhd" in merged_srcs, "dummy_util.vhd missing from merged srcs")

    return analysistest.end(env)

basic_lib_test = analysistest.make(_basic_lib_test_impl)

# --- Test: Work Library Unit Extraction ---
def _work_lib_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Check extract_sources segment
    extracted = extract_sources(target)
    asserts.equals(env, 1, len(extracted), "Expected exactly 1 segment")
    segment = extracted[0]
    asserts.equals(env, "work@93#0", segment.id)
    asserts.equals(env, "work", segment.library_name)
    asserts.equals(env, "93", segment.vhdl_version)

    srcs = [f.basename for f in segment.sources.to_list()]
    asserts.true(env, "work_source.vhd" in srcs, "work_source.vhd missing from segment sources")

    # Check group_segments
    grouped = group_segments(extracted)
    libs = {lib.id: lib for lib in grouped}
    expected_key = "work@93"
    asserts.true(env, expected_key in libs, "Key '{}' not found in libraries".format(expected_key))
    lib_struct = libs[expected_key]
    asserts.equals(env, "work", lib_struct.library_name)
    asserts.equals(env, "93", lib_struct.vhdl_version)

    return analysistest.end(env)

work_lib_test = analysistest.make(_work_lib_test_impl)

# --- Test 2: 'merge_work_lib' Logic ---
def _merge_work_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    extracted = extract_sources(target)
    grouped = group_segments(extracted)
    libs = {lib.id: lib for lib in grouped}
    target_key = "main_lib@93"

    # Ensure the main library key exists and 'work' was sealed into 'main_lib'
    asserts.true(env, target_key in libs, "Key '{}' not found in libraries".format(target_key))
    asserts.false(env, "work@93" in libs, "'work' library should have been merged and sealed into 'main_lib'")

    # Both units are consecutive and under main_lib@93, so they merge into 1 segment
    asserts.equals(env, 1, len(extracted), "Expected 1 merged segment for main_lib")
    asserts.equals(env, "main_lib@93#0", extracted[0].id)

    # Get all sources for 'main_lib'
    # We expect sources from the dependency (which is in 'work') to be merged here
    # in dependency order (work_source.vhd before main.vhd)
    srcs = [f.basename for f in libs[target_key].sources.to_list()]
    asserts.true(env, "work_source.vhd" in srcs, "Sources from 'work' library were not merged into 'main_lib'")
    asserts.true(env, "main.vhd" in srcs, "Sources from direct target missing from 'main_lib'")
    asserts.equals(env, ["work_source.vhd", "main.vhd"], srcs, "Compile order should place dependency source first")

    return analysistest.end(env)

merge_work_test = analysistest.make(_merge_work_test_impl)

# --- Test 3: Module Entity Dependencies ---
def _module_deps_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    if VhdlModuleInfo not in target:
        asserts.true(env, False, "VhdlModuleInfo provider is missing")
        return analysistest.end(env)

    info = target[VhdlModuleInfo]

    # Check VhdlModuleInfo fields
    asserts.equals(env, "top_entity", info.entity_name)
    asserts.equals(env, "32", info.generics.get("WIDTH"))
    asserts.equals(env, target.label, info.label)

    # Check extract_modules returns transitive modules in compile order (dependency first)
    modules = extract_modules(target)
    entity_names = [m.entity_name for m in modules]
    asserts.equals(env, ["sub_entity", "top_entity"], entity_names)
    asserts.equals(env, "32", modules[1].generics.get("WIDTH"))

    # Check find_module lookup
    top_mod = find_module(target, "top_entity")
    asserts.equals(env, "top_entity", top_mod.entity_name)
    asserts.equals(env, "32", top_mod.generics.get("WIDTH"))
    asserts.equals(env, "work", top_mod.library_name)

    sub_mod = find_module(target, "sub_entity")
    asserts.equals(env, "sub_entity", sub_mod.entity_name)
    asserts.equals(env, "work", sub_mod.library_name)

    # Check extract_srcs has all transitive sources in compile order
    src_names = [f.basename for f in extract_srcs(target).to_list()]
    asserts.equals(env, ["sub.vhd", "top.vhd"], src_names)

    return analysistest.end(env)

module_deps_test = analysistest.make(_module_deps_test_impl)

# --- Test 4: Translate VHDL 2008 to 93 Action ---
def _translate_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Check if output file is declared
    files = target[DefaultInfo].files.to_list()
    asserts.equals(env, 1, len(files), "Expected exactly one output file")
    asserts.true(env, files[0].basename.endswith(".vhd"), "Expected output file to end with .vhd")

    # 2. Check the action mnemonic
    actions = analysistest.target_actions(env)
    asserts.equals(env, 2, len(actions), "Expected exactly two actions to be registered")

    mnemonics = [a.mnemonic for a in actions]
    asserts.true(env, "FileWrite" in mnemonics, "Expected a FileWrite action to write the script")
    asserts.true(env, "VhdlTranslate" in mnemonics, "Expected a VhdlTranslate action to run the script")

    return analysistest.end(env)

translate_test = analysistest.make(_translate_test_impl)

# --- Test 5: Data Attribute inclusion in DefaultInfo & extract_data ---
def _data_attribute_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Check that DefaultInfo contains the extra files
    files = target[DefaultInfo].files.to_list()
    basenames = [f.basename for f in files]

    asserts.true(env, "extra_constraint.xdc" in basenames, "extra_constraint.xdc missing from DefaultInfo files")
    asserts.true(env, "dummy_util.vhd" in basenames, "dummy_util.vhd missing from DefaultInfo files")

    # Check extract_data helper
    data_files = [f.basename for f in extract_data(target).to_list()]
    asserts.true(env, "extra_constraint.xdc" in data_files, "extra_constraint.xdc missing from extract_data")

    return analysistest.end(env)

data_attribute_test = analysistest.make(_data_attribute_test_impl)

# --- Test 6: Complex Data Attribute (Filegroups & Files) ---
def _complex_data_attribute_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Check that DefaultInfo contains all the extra files (from filegroups and direct files)
    files = target[DefaultInfo].files.to_list()
    basenames = [f.basename for f in files]

    asserts.true(env, "extra_constraint.xdc" in basenames, "extra_constraint.xdc missing from DefaultInfo files")
    asserts.true(env, "vivado.tcl" in basenames, "vivado.tcl missing from DefaultInfo files")
    asserts.true(env, "meta_data.json" in basenames, "meta_data.json missing from DefaultInfo files")
    asserts.true(env, "dummy_util.vhd" in basenames, "dummy_util.vhd missing from DefaultInfo files")

    # Check extract_data helper
    data_files = [f.basename for f in extract_data(target).to_list()]
    asserts.true(env, "extra_constraint.xdc" in data_files, "extra_constraint.xdc missing from extract_data")
    asserts.true(env, "vivado.tcl" in data_files, "vivado.tcl missing from extract_data")
    asserts.true(env, "meta_data.json" in data_files, "meta_data.json missing from extract_data")

    return analysistest.end(env)

complex_data_attribute_test = analysistest.make(_complex_data_attribute_test_impl)

# --- Test 7: Interleaved Library Compile Order ---
def _interleaved_order_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Check extract_sources returns distinct segments when libraries interleave:
    # order: ip_a (base) -> ip_b (mid) -> ip_a (top)
    segments = extract_sources(target)
    asserts.equals(env, 3, len(segments), "Expected 3 compile-order segments for interleaved libraries")

    asserts.equals(env, "ip_a@2008#0", segments[0].id)
    asserts.equals(env, "ip_a", segments[0].library_name)
    asserts.equals(env, ["dummy_util.vhd"], [f.basename for f in segments[0].sources.to_list()])

    asserts.equals(env, "ip_b@2008#1", segments[1].id)
    asserts.equals(env, "ip_b", segments[1].library_name)
    asserts.equals(env, ["sub.vhd"], [f.basename for f in segments[1].sources.to_list()])

    asserts.equals(env, "ip_a@2008#2", segments[2].id)
    asserts.equals(env, "ip_a", segments[2].library_name)
    asserts.equals(env, ["top.vhd"], [f.basename for f in segments[2].sources.to_list()])

    # Check group_segments collapses segments back to one entry per (library, version)
    grouped = group_segments(segments)
    asserts.equals(env, 2, len(grouped), "Expected 2 grouped entries")
    libs = {g.id: g for g in grouped}
    asserts.true(env, "ip_a@2008" in libs)
    asserts.true(env, "ip_b@2008" in libs)
    # ip_a sources include both base and top files in order
    asserts.equals(env, ["dummy_util.vhd", "top.vhd"], [f.basename for f in libs["ip_a@2008"].sources.to_list()])

    return analysistest.end(env)

interleaved_order_test = analysistest.make(_interleaved_order_test_impl)

# --- Test 8: Dependency Graph Extraction & Serialization ---
def _graph_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # Check extract_graph
    graph = extract_graph(target)
    labels = [n.label for n in graph.nodes]
    asserts.true(env, any(["test_top_module" in l for l in labels]), "Target label missing from graph nodes: {}".format(labels))
    asserts.true(env, any(["test_sub_module" in l for l in labels]), "Dependency label missing from graph nodes: {}".format(labels))

    # Check graph_tree
    tree = graph_tree(target, include_files = True)
    asserts.true(env, "test_top_module" in tree, "Target label missing from graph_tree")
    asserts.true(env, "test_sub_module" in tree, "Dependency label missing from graph_tree")
    asserts.true(env, "top.vhd" in tree, "Source file missing from graph_tree")

    # Check graph_dot
    dot = graph_dot(target, graph_name = "test_vhdl", include_files = True)
    asserts.true(env, "digraph \"test_vhdl\"" in dot, "Expected digraph header in graph_dot")
    asserts.true(env, "test_top_module" in dot, "Target label missing from graph_dot")
    asserts.true(env, "test_sub_module" in dot, "Dependency label missing from graph_dot")

    return analysistest.end(env)

graph_test = analysistest.make(_graph_test_impl)

# --- Test 9: vhdl_graph Rule Output Files ---
def _vhdl_graph_rule_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.true(env, "test_target_graph.dot" in files, "test_target_graph.dot missing from outputs")
    asserts.true(env, "test_target_graph.txt" in files, "test_target_graph.txt missing from outputs")

    return analysistest.end(env)

vhdl_graph_rule_test = analysistest.make(_vhdl_graph_rule_test_impl)

# --- Macro to define the test suite ---
def vhdl_rules_test_suite(name):

    # 1. Setup for Basic Lib Test
    vhdl_library(
        name = "test_target_basic",
        library_name = "util_lib",
        vhdl_version = "2008",
        srcs = ["dummy_util.vhd"],
        tags = ["manual"],
    )
    basic_lib_test(
        name = "basic_lib_test",
        target_under_test = ":test_target_basic",
    )

    # 2. Setup for Merge Work Test
    vhdl_library(
        name = "test_work_dep",
        library_name = "work",
        vhdl_version = "93",
        srcs = ["work_source.vhd"],
        tags = ["manual"],
    )
    vhdl_library(
        name = "test_target_merge",
        library_name = "main_lib",
        vhdl_version = "93",
        srcs = ["main.vhd"],
        deps = [":test_work_dep"],
        merge_work_lib = True,
        tags = ["manual"],
    )
    merge_work_test(
        name = "merge_work_test",
        target_under_test = ":test_target_merge",
    )

    # 3. Setup for Module Dependencies Test
    vhdl_module(
        name = "test_sub_module",
        entity_name = "sub_entity",
        srcs = ["sub.vhd"],
        tags = ["manual"],
    )
    vhdl_module(
        name = "test_top_module",
        entity_name = "top_entity",
        srcs = ["top.vhd"],
        generics = {"WIDTH": "32"},
        deps = [":test_sub_module"],
        tags = ["manual"],
    )
    module_deps_test(
        name = "module_deps_test",
        target_under_test = ":test_top_module",
    )

    # 4. Setup for Translate 2008 to 93 Test
    vhdl_translate(
        name = "test_target_translate",
        src = ":test_target_basic",
        entity_name = "dummy_entity",
        tool_simulator = "ghdl",
        tool_version = "mock",
        tags = ["manual"],
    )
    translate_test(
        name = "translate_test",
        target_under_test = ":test_target_translate",
    )

    # 5. Setup for Data Attribute Test
    vhdl_library(
        name = "test_target_data",
        library_name = "data_lib",
        vhdl_version = "2008",
        srcs = ["dummy_util.vhd"],
        data = ["extra_constraint.xdc"],
        tags = ["manual"],
    )
    data_attribute_test(
        name = "data_attribute_test",
        target_under_test = ":test_target_data",
    )

    vhdl_module(
        name = "test_module_data",
        entity_name = "data_entity",
        srcs = ["dummy_util.vhd"],
        data = ["extra_constraint.xdc"],
        tags = ["manual"],
    )
    data_attribute_test(
        name = "module_data_attribute_test",
        target_under_test = ":test_module_data",
    )

    # 6. Setup for Complex Data Attribute Test
    native.filegroup(
        name = "test_constraints_fg",
        srcs = ["extra_constraint.xdc"],
        tags = ["manual"],
    )
    native.filegroup(
        name = "test_vivado_script_fg",
        srcs = ["vivado.tcl"],
        tags = ["manual"],
    )
    vhdl_library(
        name = "test_target_complex_data",
        library_name = "complex_data_lib",
        vhdl_version = "2008",
        srcs = ["dummy_util.vhd"],
        data = [
            ":test_constraints_fg",
            ":test_vivado_script_fg",
            "meta_data.json",
        ],
        tags = ["manual"],
    )
    complex_data_attribute_test(
        name = "complex_data_attribute_test",
        target_under_test = ":test_target_complex_data",
    )

    work_lib_test(
        name = "work_lib_test",
        target_under_test = ":test_work_dep",
    )

    # 7. Setup for Interleaved Library Compile Order Test
    # ip_a (base) -> ip_b (mid) -> ip_a (top)
    vhdl_library(
        name = "test_interleaved_base",
        library_name = "ip_a",
        vhdl_version = "2008",
        srcs = ["dummy_util.vhd"],
        tags = ["manual"],
    )
    vhdl_library(
        name = "test_interleaved_mid",
        library_name = "ip_b",
        vhdl_version = "2008",
        srcs = ["sub.vhd"],
        deps = [":test_interleaved_base"],
        tags = ["manual"],
    )
    vhdl_library(
        name = "test_interleaved_top",
        library_name = "ip_a",
        vhdl_version = "2008",
        srcs = ["top.vhd"],
        deps = [":test_interleaved_mid"],
        tags = ["manual"],
    )
    interleaved_order_test(
        name = "interleaved_order_test",
        target_under_test = ":test_interleaved_top",
    )

    # 8. Setup for Dependency Graph Test
    graph_test(
        name = "graph_test",
        target_under_test = ":test_top_module",
    )

    # 9. Setup for vhdl_graph Rule Test
    vhdl_graph(
        name = "test_target_graph",
        deps = [":test_top_module"],
        include_files = True,
        tags = ["manual"],
    )
    vhdl_graph_rule_test(
        name = "vhdl_graph_rule_test",
        target_under_test = ":test_target_graph",
    )

    # Main test suite entry point
    native.test_suite(
        name = name,
        tests = [
            ":basic_lib_test",
            ":work_lib_test",
            ":merge_work_test",
            ":module_deps_test",
            ":translate_test",
            ":data_attribute_test",
            ":module_data_attribute_test",
            ":complex_data_attribute_test",
            ":interleaved_order_test",
            ":graph_test",
            ":vhdl_graph_rule_test",
        ],
    )
