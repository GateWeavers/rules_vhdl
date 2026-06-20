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

class VUnit:
    @classmethod
    def from_argv(cls, args):
        print(f"Mock VUnit initialized with args: {args}")
        return cls()
    
    def library(self, name):
        print(f"Mock VUnit library: {name}")
        return self
    
    def add_library(self, name):
        print(f"Mock VUnit add_library: {name}")
        return self
    
    def add_source_files(self, files, vhdl_standard):
        print(f"Mock VUnit add_source_files: {files} (std: {vhdl_standard})")
    
    def main(self):
        print("Mock VUnit main called. Simulation successful!")
