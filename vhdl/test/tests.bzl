load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest")
load("//vhdl:vhdl.bzl", "vhdl_library", "vhdl_module", "VhdlLibraryInfo", "VhdlModuleInfo")

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

    # Main test suite entry point
    native.test_suite(
        name = name,
        tests = [
            ":basic_lib_test",
            ":merge_work_test",
            ":module_deps_test",
        ],
    )