from sim.vunit_bazel_helper import get_vunit_from_bazel

def main():
    print("HELLO FROM CUSTOM RUNNER!")
    vu = get_vunit_from_bazel()
    vu.add_vhdl_builtins()
    vu.main()

if __name__ == "__main__":
    main()
