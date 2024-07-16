import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

from mig import simulate_mig, generate_memory

async def reset(reset):
    reset.value = 1
    await Timer(10,units="ns")
    reset.value = 0
    await Timer(10,units="ns")

def cmd_assent(valid,ready):
    return (valid.value == 1 and ready.value == 1)


async def handle_mmio(dut):
    dut.uart_tx_ready.value = 1
    while True:
        await RisingEdge(dut.ui_clk)
        if (dut.uart_tx_valid.value == 1):
            dut.uart_tx_ready.value = 0
            await Timer(1000,units="ns")
            dut.uart_tx_ready.value = 1
            print("[PY] uart byte: %x" % dut.uart_tx_data.value)
        if (dut.processor_done == 1):
            print("[PY] EXIT")
            return True

@cocotb.test()
async def test_a(dut):
    """ give memory responses via python input """

    memory = generate_memory('mem.vmh')
    
    await cocotb.start( simulate_mig(dut,memory) )
    dut.rst_in.value = 0
    await Timer(10,units="ns")
    dut.rst_in.value = 1
    await Timer(30,units="ns")
    dut.rst_in.value = 0
    
    await handle_mmio(dut)

                
