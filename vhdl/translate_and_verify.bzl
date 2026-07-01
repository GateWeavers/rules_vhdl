load("//vhdl:vhdl.bzl", "vhdl_library", "vhdl_translate", "vhdl_wrapper")
load("//sim:sim.bzl", "vhdl_test")
load("//sim:vunit_rules.bzl", "vunit_sim")
load("//sim:cocotb_rules.bzl", "cocotb_sim")

def vhdl_translate_and_verify(
    name,
    src,
    entity_name,
    testbench_srcs = [],
    testbench_entity = None,
    test_module = None,
    test_type = "vhdl", # "vhdl", "vunit", or "cocotb"
    preserve_ports = True,
    simulator = None,
    sim_args = [],
    deps = [],
    **kwargs
):
    """Translates a VHDL entity to VHDL 93 and runs equivalence checks against a testbench."""
    
    # 1. Translation
    translated_vhd = name + "_translated_vhd"
    vhdl_translate(
        name = translated_vhd,
        src = src,
        entity_name = entity_name,
        preserve_ports = preserve_ports,
        simulator = simulator,
    )
    
    # 2. Translated Library (compiled to a unique flat library to avoid name collision with wrapper)
    translated_lib = name + "_translated_lib"
    flat_library_name = name + "_flat_lib"
    vhdl_library(
        name = translated_lib,
        srcs = [":" + translated_vhd],
        library_name = flat_library_name,
    )
    
    # 3. Wrapper (if ports are flattened)
    if not preserve_ports:
        wrapper_target = name + "_wrapper"
        vhdl_wrapper(
            name = wrapper_target,
            src = src, # Pass original src containing record type package
            entity_name = entity_name,
            reverse = True,
            library_name = flat_library_name,
            wrapper_entity = entity_name,
            simulator = simulator,
        )
        
        # Wrapped translated library (exposing record ports)
        wrapped_lib = name + "_wrapped_lib"
        vhdl_library(
            name = wrapped_lib,
            srcs = [":" + wrapper_target],
            library_name = "work",
            deps = [":" + translated_lib, src],
        )
        dut_target = ":" + wrapped_lib
    else:
        dut_target = ":" + translated_lib

    # 4. Generate tests if testbench parameters are specified
    if testbench_srcs or test_module:
        orig_test_name = name + "_orig_test"
        trans_test_name = name + "_translated_test"
        
        if test_type == "vhdl":
            vhdl_test(
                name = orig_test_name,
                srcs = testbench_srcs,
                dut = src,
                testbench_entity = testbench_entity,
                simulator = simulator,
                sim_args = sim_args,
                **kwargs
            )
            vhdl_test(
                name = trans_test_name,
                srcs = testbench_srcs,
                dut = dut_target,
                testbench_entity = testbench_entity,
                simulator = simulator,
                sim_args = sim_args,
                **kwargs
            )
        elif test_type == "vunit":
            vunit_sim(
                name = orig_test_name,
                srcs = testbench_srcs,
                dut = src,
                simulator = simulator,
                deps = deps,
                **kwargs
            )
            vunit_sim(
                name = trans_test_name,
                srcs = testbench_srcs,
                dut = dut_target,
                simulator = simulator,
                deps = deps,
                **kwargs
            )
        elif test_type == "cocotb":
            cocotb_sim(
                name = orig_test_name,
                srcs = testbench_srcs,
                dut = src,
                hdl_toplevel = entity_name,
                test_module = test_module,
                simulator = simulator,
                **kwargs
            )
            cocotb_sim(
                name = trans_test_name,
                srcs = testbench_srcs,
                dut = dut_target,
                hdl_toplevel = entity_name,
                test_module = test_module,
                simulator = simulator,
                **kwargs
            )
        else:
            fail("Unsupported test_type: " + test_type)
