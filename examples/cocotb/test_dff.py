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
