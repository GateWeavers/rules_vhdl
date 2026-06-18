import os
import sys

from pathlib import Path
from cocotb_tools.runner import get_runner

def run_cocotb_bazel():

    build_dir = Path("cocotb_build")
    build_dir.mkdir(exist_ok=True)

    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        build_dir=build_dir,
        always=True,
    )

    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_module,
        results_xml=results_xml,
    )

if __name__ == "__main__":
    run_cocotb_bazel()