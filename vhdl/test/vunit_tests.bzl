load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest")
load("//sim:vunit_rules.bzl", "vunit_context")
load("//vhdl:vhdl.bzl", "vhdl_library")

def _vunit_context_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Check if config JSON is created
    found_config = False
    for f in target[DefaultInfo].files.to_list():
        if f.basename.endswith("_config.json"):
            found_config = True
            break
    asserts.true(env, found_config, "Config JSON missing from DefaultInfo files")
    
    # 2. Check runfiles (should contain mock binary, sources and config)
    runfiles = target[DefaultInfo].default_runfiles.files.to_list()
    has_mock_bin = False
    has_config = False
    for f in runfiles:
        if "mock_bin.sh" in f.basename:
            has_mock_bin = True
        if f.basename.endswith("_config.json"):
            has_config = True
    
    asserts.true(env, has_mock_bin, "Mock binary missing from runfiles")
    asserts.true(env, has_config, "Config JSON missing from runfiles")

    return analysistest.end(env)

vunit_context_analysis_test = analysistest.make(_vunit_context_analysis_test_impl)

def vunit_test_suite(name):
    vhdl_library(
        name = "test_vunit_lib",
        srcs = ["dummy_util.vhd"],
        library_name = "work",
        tags = ["manual"],
    )

    vunit_context(
        name = "test_vunit_ctx",
        dut = ":test_vunit_lib",
        srcs = ["main.vhd"],
        tool_simulator = "ghdl",
        tool_version =  "mock",
        tags = ["manual"],
    )

    vunit_context_analysis_test(
        name = "vunit_context_analysis_test",
        target_under_test = ":test_vunit_ctx",
    )

    native.test_suite(
        name = name,
        tests = [
            ":vunit_context_analysis_test",
        ],
    )
