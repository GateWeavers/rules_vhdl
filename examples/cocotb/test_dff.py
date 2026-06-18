import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock

@cocotb.test()
async def dff_basic_test(dut):
    """Test for D-Flip-Flop"""

    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await RisingEdge(dut.clk)
    dut.d.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.q.value == 1, f"Expected 1, got {dut.q.value}"

    await RisingEdge(dut.clk)
    dut.d.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    assert dut.q.value == 0, f"Expected 0, got {dut.q.value}"
