from sim.vunit_bazel_helper import get_vunit_from_bazel, add_lib_from_bazel
import sys

# Try to import crc to prove dependency is there
try:
    from crc import Calculator, Configuration
    CRC_AVAILABLE = True
except ImportError:
    CRC_AVAILABLE = False

def main():
    if CRC_AVAILABLE:
        config = Configuration(width=8, polynomial=0x07, init_value=0x00, final_xor_value=0x00)
        calculator = Calculator(config)
        result = calculator.checksum(b"123456789")
        print(f"CRC-8 result: {result}")
    else:
        print("ERROR: crc library not found!")
        sys.exit(1)

    vu = get_vunit_from_bazel()
    vu.add_vhdl_builtins()
    add_lib_from_bazel(vu)
    vu.main()

if __name__ == "__main__":
    main()
