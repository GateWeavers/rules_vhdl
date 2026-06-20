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