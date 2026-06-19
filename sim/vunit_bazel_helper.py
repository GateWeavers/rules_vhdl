import os
import sys
import json
import subprocess
import shutil
import xml.etree.ElementTree as ET
from vunit import VUnit

def is_coverage_enabled():
    return os.environ.get("COVERAGE") == "1" and os.environ.get("VUNIT_COVERAGE_DISABLED") != "1"

def make_path_relative_to_workspace(filename):
    abs_filename = os.path.abspath(filename)
    parts = abs_filename.split(os.sep)
    for i in range(len(parts)):
        candidate = os.path.join(*parts[i:])
        if candidate and os.path.exists(candidate) and os.path.isfile(candidate):
            return candidate
    return filename

def convert_cobertura_to_lcov(xml_path, lcov_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
    except Exception as e:
        print(f"Error parsing Cobertura XML: {e}")
        return False

    with open(lcov_path, 'w') as out:
        for cls in root.findall(".//class"):
            filename = cls.get("filename")
            if not filename:
                continue

            filename = make_path_relative_to_workspace(filename)
            out.write(f"SF:{filename}\n")

            lines = cls.find("lines")
            lf = 0
            lh = 0
            if lines is not None:
                for line in lines.findall("line"):
                    num = line.get("number")
                    hits = line.get("hits")
                    if num is not None and hits is not None:
                        out.write(f"DA:{num},{hits}\n")
                        lf += 1
                        if int(hits) > 0:
                            lh += 1

            out.write(f"LF:{lf}\n")
            out.write(f"LH:{lh}\n")
            out.write("end_of_record\n")

    return True

def fallback_merge_nvc_databases(vunit_out_dir, db_file, nvc_bin):
    ncdb_files = []
    if os.path.exists(vunit_out_dir):
        for root, dirs, files in os.walk(vunit_out_dir):
            for name in dirs + files:
                if name.endswith((".ncdb", ".covdb")):
                    full_path = os.path.join(root, name)
                    if full_path not in ncdb_files:
                        ncdb_files.append(full_path)
                     
    print(f"Found {len(ncdb_files)} individual NVC coverage databases.")
    
    if not ncdb_files:
        print("No NVC coverage databases found in vunit_out, skipping coverage reporting.")
        return False

    # Clean up existing database file/directory before writing a new one
    if os.path.exists(db_file):
        if os.path.isdir(db_file):
            shutil.rmtree(db_file)
        else:
            os.remove(db_file)

    if len(ncdb_files) == 1:
        src = ncdb_files[0]
        if os.path.isdir(src):
            shutil.copytree(src, db_file)
        else:
            shutil.copy2(src, db_file)
        return True
    else:
        try:
            merge_cmd = [nvc_bin, "--cover-merge", "-o", db_file] + ncdb_files
            print(f"Merging coverage databases using command: {' '.join(merge_cmd)}")
            subprocess.check_call(merge_cmd)
            return True
        except Exception as e:
            print(f"Failed to merge NVC coverage databases manually: {e}")
            return False

def collect_nvc_coverage(vu, results):
    coverage_output_file = os.environ.get("COVERAGE_OUTPUT_FILE")
    if not coverage_output_file:
        print("COVERAGE_OUTPUT_FILE not set, skipping coverage reporting.")
        return

    nvc_path = os.environ.get("VUNIT_NVC_PATH")
    nvc_bin = os.path.join(nvc_path, "nvc") if nvc_path else "nvc"
    db_name = "coverage_data"
    db_file = db_name + ".ncdb"
    
    # Try calling VUnit merge first
    vunit_merged = False
    try:
        results.merge_coverage(file_name=db_name)
        if os.path.exists(db_file):
            vunit_merged = True
    except Exception as e:
        print(f"VUnit merge_coverage failed: {e}")

    # Fallback to finding .ncdb/.covdb files and merging/copying them manually
    if not vunit_merged:
        success = fallback_merge_nvc_databases(vu._output_path, db_file, nvc_bin)
        if not success:
            return

    if not os.path.exists(db_file):
        print(f"Coverage database {db_file} not found after manual merge/copy.")
        return

    xml_file = "cobertura.xml"
    exported = False
    export_cmds = [
        [nvc_bin, "--cover-export", db_file, "--format=cobertura", "-o", xml_file],
        [nvc_bin, f"--cover-export={xml_file}", db_file],
        [nvc_bin, "--cover-export", db_file, "-o", xml_file]
    ]
    for cmd in export_cmds:
        try:
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                exported = True
                break
        except Exception:
            pass

    if not exported:
        print("Failed to export NVC coverage database to Cobertura XML.")
        return

    if not os.path.exists(xml_file):
        print("Cobertura XML file not found after export.")
        return

    try:
        success = convert_cobertura_to_lcov(xml_file, coverage_output_file)
        if success:
            print(f"Successfully wrote LCOV coverage report to {coverage_output_file}")
        else:
            print("Failed to convert Cobertura XML to LCOV.")
    except Exception as e:
        print(f"Error during Cobertura to LCOV conversion: {e}")

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

    # Intercept vu.main to process coverage after tests run
    original_main = vu.main
    def wrapped_main(*args, **kwargs):
        if is_coverage_enabled():
            sim_name = vu.get_simulator_name()
            if sim_name == "nvc":
                # Do NOT set VUnit's enable_coverage to True for NVC to prevent VUnit from passing
                # the unsupported '--cover-file' argument to older NVC versions (like 1.12.1).
                # NVC will write the coverage database to its default path (<toplevel>.ncdb).
                vu.set_sim_option("nvc.elab_flags", ["--cover=branch,statement"])
            elif sim_name == "ghdl":
                print("WARNING: Code coverage is not supported for GHDL (both mcode and LLVM backends) in this ruleset. Please use NVC for code coverage.")

        user_post_run = kwargs.get("post_run", None)
        
        def coverage_post_run(results):
            if user_post_run:
                try:
                    user_post_run(results)
                except Exception as e:
                    print(f"Error in user post_run: {e}")
            
            if is_coverage_enabled() and vu.get_simulator_name() == "nvc":
                try:
                    collect_nvc_coverage(vu, results)
                except Exception as e:
                    print(f"Error collecting coverage: {e}")
                    
        if is_coverage_enabled() and vu.get_simulator_name() == "nvc":
            kwargs["post_run"] = coverage_post_run
            
        return original_main(*args, **kwargs)
        
    vu.main = wrapped_main
            
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
        vu.set_sim_option("nvc.global_flags",["-L"+lib_path], allow_empty=True)