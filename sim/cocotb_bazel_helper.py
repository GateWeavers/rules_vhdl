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

import os
import sys
import json
import importlib
import xml.etree.ElementTree as ET
from pathlib import Path
from cocotb_tools.runner import get_runner

def get_config():
    config_path = os.environ.get("COCOTB_BAZEL_CONFIG")
    if not config_path or not os.path.exists(config_path):
        print(f"Error: COCOTB_BAZEL_CONFIG ({config_path}) not set or not found.")
        sys.exit(1)
    with open(config_path, 'r') as f:
        return json.load(f)

def setup_env(config):
    sim_type = config['simulator_type']
    binary_dir = os.path.dirname(os.path.abspath(config['binary_path']))
    os.environ["PATH"] = binary_dir + os.pathsep + os.environ.get("PATH", "")
    if sim_type == "ghdl":
        os.environ["GHDL_PREFIX"] = os.path.join(binary_dir, "..", "lib", "ghdl")
    return sim_type

def check_results():
    results_xml = os.environ.get("XML_OUTPUT_FILE", "results.xml")
    if os.path.exists(results_xml):
        root = ET.parse(results_xml).getroot()
        failures = len(root.findall(".//failure")) + len(root.findall(".//error"))
        if failures > 0:
            print(f"ERROR: Cocotb simulation failed with {failures} failures/errors.")
            sys.exit(1)
    else:
        print(f"ERROR: Results XML not found at {results_xml}")
        sys.exit(1)

def run():
    config = get_config()
    sim_type = setup_env(config)
    
    user_module_name = os.environ.get("COCOTB_USER_RUNNER")
    if user_module_name:
        # Load and run user module
        try:
            module = importlib.import_module(user_module_name)
            if hasattr(module, "main"):
                module.main()
            else:
                print(f"ERROR: Custom runner module '{user_module_name}' has no main() function.")
                sys.exit(1)
        except Exception as e:
            print(f"ERROR: Failed to run custom runner '{user_module_name}': {e}")
            sys.exit(1)
    else:
        # Default run logic
        runner = get_runner(sim_type)
        sources = [os.path.abspath(f['file']) for files in config['libraries'].values() for f in files]
        build_dir = Path("cocotb_build")
        build_dir.mkdir(exist_ok=True)

        runner.build(
            sources=sources,
            hdl_toplevel=config['hdl_toplevel'],
            build_dir=build_dir,
            always=True,
        )

        results_xml = os.environ.get("XML_OUTPUT_FILE", "results.xml")
        runner.test(
            hdl_toplevel=config['hdl_toplevel'],
            test_module=config['test_module'],
            results_xml=results_xml,
        )

    # Always check results at the end
    check_results()

if __name__ == "__main__":
    run()
