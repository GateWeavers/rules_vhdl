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