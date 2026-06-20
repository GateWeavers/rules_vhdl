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
load("//sim:sim.bzl", "vhdl_test")
load("//vhdl:vhdl.bzl", "vhdl_library")

def _vhdl_test_analysis_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Check if executable is created
    asserts.true(env, target[DefaultInfo].files_to_run.executable != None, "Executable is missing")
    
    # 2. Check runfiles (should contain mock binary and sources)
    runfiles = target[DefaultInfo].default_runfiles.files.to_list()
    has_mock_bin = False
    for f in runfiles:
        if "mock_bin.sh" in f.basename:
            has_mock_bin = True
            break
    
    asserts.true(env, has_mock_bin, "Mock binary missing from runfiles")

    return analysistest.end(env)

vhdl_test_analysis_test = analysistest.make(_vhdl_test_analysis_test_impl)

def sim_test_suite(name):
    vhdl_library(
        name = "test_lib",
        srcs = ["dummy_util.vhd"],
        library_name = "work",
        tags = ["manual"],
    )

    vhdl_test(
        name = "test_ghdl_sim",
        srcs = ["main.vhd"],
        dut = ":test_lib",
        testbench_entity = "main",
        tool_simulator = "ghdl",
        tool_version = "mock",
        # simulator = "//simulator:mock_ghdl_toolchain",
        tags = ["manual"],
    )

    vhdl_test_analysis_test(
        name = "ghdl_sim_analysis_test",
        target_under_test = ":test_ghdl_sim",
    )

    native.test_suite(
        name = name,
        tests = [
            ":ghdl_sim_analysis_test",
        ],
    )
