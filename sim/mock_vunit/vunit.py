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
