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

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest")
load("//vhdl:vhdl.bzl", "vhdl_library", "vhdl_module", "vhdl_translate", "VhdlLibraryInfo", "VhdlModuleInfo")

# --- Test 1: Basic Library Creation & Key Generation ---
def _basic_lib_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Check provider existence
    if VhdlLibraryInfo not in target:
        asserts.true(env, False, "VhdlLibraryInfo provider is missing")
        return analysistest.end(env)

    # 2. Check the dictionary key format (lib_name@version)
    libs = target[VhdlLibraryInfo].libraries
    expected_key = "util_lib@2008"
    
    asserts.true(env, expected_key in libs, "Key '{}' not found in libraries".format(expected_key))
    
    # 3. Check library name and version in struct
    lib_struct = libs[expected_key]
    asserts.equals(env, "util_lib", lib_struct.library_name)
    asserts.equals(env, "2008", lib_struct.vhdl_version)

    return analysistest.end(env)

basic_lib_test = analysistest.make(_basic_lib_test_impl)

# --- Test 2: 'merge_work_lib' Logic ---
def _merge_work_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    
    libs = target[VhdlLibraryInfo].libraries
    target_key = "main_lib@93"
    
    # Ensure the main library key exists
    asserts.true(env, target_key in libs)
    
    # Get all sources for 'main_lib'
    # We expect sources from the dependency (which is in 'work') to be merged here
    # because merge_work_lib = True
    srcs = libs[target_key].sources.to_list()
    
    # Check for the presence of the work library file
    has_work_file = False
    for f in srcs:
        if "work_source.vhd" in f.basename:
            has_work_file = True
            break
            
    asserts.true(env, has_work_file, "Sources from 'work' library were not merged into 'main_lib'")
    
    return analysistest.end(env)

merge_work_test = analysistest.make(_merge_work_test_impl)

# --- Test 3: Module Entity Dependencies (Depset check) ---
def _module_deps_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    if VhdlModuleInfo not in target:
        asserts.true(env, False, "VhdlModuleInfo provider is missing")
        return analysistest.end(env)

    info = target[VhdlModuleInfo]
    
    # Check generics
    asserts.equals(env, "32", info.generics.get("WIDTH"))

    # Check transitive entities
    # Expecting: 'top_entity' (self) AND 'sub_entity' (dependency)
    entities = info.dep_entities.to_list()
    
    asserts.true(env, "top_entity" in entities, "Missing own entity name")
    asserts.true(env, "sub_entity" in entities, "Missing dependency entity name")
    
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

# --- Macro to define the test suite ---
def vhdl_rules_test_suite(name):
    
    # 1. Setup for Basic Lib Test
    vhdl_library(
        name = "test_target_basic",
        library_name = "util_lib",
        vhdl_version = "2008",
        srcs = ["dummy_util.vhd"],
        tags = ["manual"], # Prevents normal build attempts
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

    # Main test suite entry point
    native.test_suite(
        name = name,
        tests = [
            ":basic_lib_test",
            ":merge_work_test",
            ":module_deps_test",
            ":translate_test",
        ],
    )