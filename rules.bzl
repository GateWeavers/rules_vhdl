load("//vhdl:defs.bzl","vhdl_library","vhdl_module","VhdlLibraryInfo","extract_sources","vhdl_translate","vhdl_wrapper","vhdl_translate_and_verify")
load("//sim:defs.bzl","vhdl_test","vunit_sim","cocotb_sim")
load("//formal:defs.bzl","vhdl_formal_test","vhdl_bmc_test","vhdl_cover_test","vhdl_prove_test","vhdl_eqy_test")

# base vhdl rules
vhdl_library = vhdl_library
vhdl_module = vhdl_module
VhdlLibraryInfo = VhdlLibraryInfo
extract_sources = extract_sources
vhdl_translate = vhdl_translate
vhdl_wrapper = vhdl_wrapper
vhdl_translate_and_verify = vhdl_translate_and_verify

# vhdl simulation rules
vhdl_test = vhdl_test
vunit_sim = vunit_sim
cocotb_sim = cocotb_sim

# formal verication rules
vhdl_formal_test = vhdl_formal_test
vhdl_bmc_test = vhdl_bmc_test
vhdl_cover_test = vhdl_cover_test
vhdl_prove_test = vhdl_prove_test
vhdl_eqy_test = vhdl_eqy_test
