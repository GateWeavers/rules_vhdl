#  Copyright 2026 Nocilis
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#      http://www.apache.org/licenses/LICENSE-2.0
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

load("@bazel_skylib//lib:unittest.bzl", "asserts", "analysistest")
load("//vhdl:defs.bzl", "vhdl_library")
load("//formal:defs.bzl", "vhdl_formal_test", "vhdl_bmc_test", "vhdl_cover_test")

def _formal_test_analysis_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    # 1. Verify executable is present
    asserts.true(env, target[DefaultInfo].files_to_run.executable != None, "Executable missing")

    # 2. Verify runfiles include generated .sby config
    runfiles = target[DefaultInfo].default_runfiles.files.to_list()
    has_sby = False
    for f in runfiles:
        if f.basename.endswith(".sby"):
            has_sby = True
            break
    asserts.true(env, has_sby, "Generated .sby file missing from runfiles")

    return analysistest.end(env)

formal_test_analysis_test = analysistest.make(_formal_test_analysis_impl)

def formal_test_suite(name):
    vhdl_library(
        name = "dummy_dut_lib",
        srcs = ["counter.vhd"],
        library_name = "work",
        vhdl_version = "2008",
        tags = ["manual"],
    )

    vhdl_formal_test(
        name = "test_formal_target",
        dut = ":dummy_dut_lib",
        top_entity = "counter",
        psl_srcs = ["counter_props.psl"],
        mode = "bmc",
        depth = 15,
        engine = "smtbmc yices",
        tags = ["manual"],
    )

    vhdl_bmc_test(
        name = "test_bmc_macro",
        dut = ":dummy_dut_lib",
        top_entity = "counter",
        tags = ["manual"],
    )

    vhdl_cover_test(
        name = "test_cover_macro",
        dut = ":dummy_dut_lib",
        top_entity = "counter",
        tags = ["manual"],
    )

    formal_test_analysis_test(
        name = "formal_analysis_test",
        target_under_test = ":test_formal_target",
    )

    formal_test_analysis_test(
        name = "bmc_macro_analysis_test",
        target_under_test = ":test_bmc_macro",
    )

    formal_test_analysis_test(
        name = "cover_macro_analysis_test",
        target_under_test = ":test_cover_macro",
    )

    native.test_suite(
        name = name,
        tests = [
            ":formal_analysis_test",
            ":bmc_macro_analysis_test",
            ":cover_macro_analysis_test",
        ],
    )
