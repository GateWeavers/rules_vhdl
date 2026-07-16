load("//vhdl:vhdl.bzl", _vhdl_library = "vhdl_library", _vhdl_module = "vhdl_module", _vhdl_translate = "vhdl_translate", _vhdl_wrapper = "vhdl_wrapper")
load("//vhdl:translate_and_verify.bzl", _vhdl_translate_and_verify = "vhdl_translate_and_verify")

vhdl_library = _vhdl_library
vhdl_module = _vhdl_module
vhdl_translate = _vhdl_translate
vhdl_wrapper = _vhdl_wrapper
vhdl_translate_and_verify = _vhdl_translate_and_verify
