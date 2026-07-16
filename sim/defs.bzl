load("//sim:sim.bzl", _vhdl_test = "vhdl_test")
load("//sim:vunit_rules.bzl", _vunit_sim = "vunit_sim")
load("//sim:cocotb_rules.bzl", _cocotb_sim = "cocotb_sim")

vhdl_test = _vhdl_test
vunit_sim = _vunit_sim
cocotb_sim = _cocotb_sim
