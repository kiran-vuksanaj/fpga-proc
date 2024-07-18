import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

async def generate_clock(clk):
    """ generate clock pulses """
    while True:
        clk.value = 0
        await Timer(5,units="ns")
        clk.value = 1
        await Timer(5,units="ns")

@cocotb.test()
async def test_a(dut):
    await cocotb.start( generate_clock(dut.clka) )

    dut.rsta.value = 0
    await Timer(10,units="ns")
    dut.rsta.value = 1
    dut.addra.value = 0
    dut.dina.value = 0
    dut.wea.value = 0
    dut.ena.value = 0
    dut.regcea.value = 0
    await Timer(10,units="ns")
    dut.rsta.value = 0
    dut.regcea.value = 1
    dut.ena.value = 1
    await Timer(10,units="ns")

    dut.addra.value = 12
    dut.wea.value = 1
    dut.dina.value = 0xFEED
    await Timer(10,units="ns")
    dut.wea.value = 0
    dut.dina.value = 0
    await Timer(30,units="ns")
                        
