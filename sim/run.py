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
import json
import sys
from vunit import VUnit

def run_vunit_bazel():

    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        print("Erreur: Ce script doit être exécuté via 'bazel test'")
        sys.exit(1)

    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)

    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    
    ghdl_binary_path = os.path.abspath(config['ghdl_binary'])
    ghdl_dir = os.path.dirname(ghdl_binary_path)
    
    os.environ["VUNIT_GHDL_PATH"] = ghdl_dir
    
    print(f"DEBUG: VUnit configured with GHDL at {ghdl_dir}")

    argv = sys.argv[:]
    
    xml_output = os.environ.get("XML_OUTPUT_FILE")
    if xml_output:
        argv.extend(["--xunit-xml", xml_output])


    vu = VUnit.from_argv(argv)

    for lib_name, files in config['libraries'].items():
        try:
            lib = vu.library(lib_name)
        except KeyError:
            lib = vu.add_library(lib_name)
            
        for file_entry in files:
            lib.add_source_files(file_entry['file'], vhdl_standard=file_entry['version'])


    vu.main()

if __name__ == "__main__":
    run_vunit_bazel()