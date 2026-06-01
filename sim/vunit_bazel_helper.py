import os
import sys
import json
from vunit import VUnit

def get_vunit_from_bazel():
    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        print("Error: VUNIT_BAZEL_CONFIG not set.")
        sys.exit(1)
        
    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)

    sim_type = config['simulator_type']
    binary_path = os.path.abspath(config['binary_path'])
    binary_dir = os.path.dirname(binary_path)

    if sim_type == "ghdl":
        os.environ["VUNIT_SIMULATOR"] = "ghdl"
        os.environ["VUNIT_GHDL_PATH"] = binary_dir
        os.environ["GHDL_PREFIX"] = os.path.join(binary_dir, "..", "lib", "ghdl")
    elif sim_type == "nvc":
        os.environ["VUNIT_SIMULATOR"] = "nvc"
        os.environ["VUNIT_NVC_PATH"] = binary_dir

    # Expand environment variables in arguments (e.g. $XML_OUTPUT_FILE)
    arg = sys.argv[1:]
    args = [os.path.expandvars(a) for a in arg]
    
    if "XML_OUTPUT_FILE" in os.environ and "--xunit-xml" not in args:
        args.extend(["--xunit-xml", os.environ["XML_OUTPUT_FILE"]])

    vu = VUnit.from_argv(args)
            
    return vu

def add_lib_from_bazel(vu):
    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        print("Error: VUNIT_BAZEL_CONFIG not set.")
        sys.exit(1)
        
    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)
    
    for lib_name, files in config['libraries'].items():
        try:
            lib = vu.library(lib_name)
        except KeyError:
            lib = vu.add_library(lib_name)
            
        for file_entry in files:
            lib.add_source_files(file_entry['file'], vhdl_standard=file_entry['version'])
    return vu

def set_nvc_options(vu):
    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        return

    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)

    nvc_opts = []
    if vu.get_simulator_name() == "nvc":
        # nvc_opts.extend(["-L", os.path.abspath(library_path)])
        lib_path = os.path.normpath(os.path.join(os.getenv("VUNIT_NVC_PATH") ,"../lib"))
        vu.add_compile_option("nvc.global_flags",["-L"+lib_path])
        vu.set_sim_option("nvc.global_flags",["-L"+lib_path])