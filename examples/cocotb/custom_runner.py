from sim.cocotb_bazel_helper import get_config, setup_env
from cocotb_tools.runner import get_runner
from pathlib import Path
import os

def main():
    print("HELLO FROM CUSTOM COCOTB RUNNER!")
    
    config = get_config()
    sim_type = config['simulator_type']
    
    runner = get_runner(sim_type)
    
    # Gather sources
    sources = []
    for lib_name, files in config['libraries'].items():
        for f in files:
            sources.append(os.path.abspath(f['file']))
            
    build_dir = Path("cocotb_custom_build")
    build_dir.mkdir(exist_ok=True)
    
    # Build
    runner.build(
        sources=sources,
        hdl_toplevel=config['hdl_toplevel'],
        build_dir=build_dir,
        always=True,
    )
    
    # Run
    runner.test(
        hdl_toplevel=config['hdl_toplevel'],
        test_module=config['test_module'],
        results_xml=os.environ.get("XML_OUTPUT_FILE", "results.xml"),
    )

    print(os.environ.get("XML_OUTPUT_FILE", "results.xml"))