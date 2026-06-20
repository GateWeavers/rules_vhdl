#!/usr/bin/env python3

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

from sim.vunit_bazel_helper import get_vunit_from_bazel,add_lib_from_bazel
from pathlib import Path
import sys

vu = get_vunit_from_bazel()
vu.add_vhdl_builtins()
vu.add_osvvm()
vu.add_verification_components()

add_lib_from_bazel(vu)

vu.main()