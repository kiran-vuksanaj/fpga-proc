import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

async def generate_clock(dut):
    """ generate clock pulses """
    while True:
        dut.clk_in.value = 0
        await Timer(5,units="ns")
        dut.clk_in.value = 1
        await Timer(5,units="ns")

async def reset(dut):
    dut.rst_in.value = 1
    await Timer(10,units="ns")
    dut.rst_in.value = 0
    await Timer(10,units="ns")


def cmd_assent(valid,ready):
    return (valid.value == 1 and ready.value == 1)

async def deliver_value(clk,valid,ready,wire,data):
    valid.value = 1
    wire.value = data
    await RisingEdge(clk)
    while (not cmd_assent(valid,ready)):
        await Timer(10,units="ns")
    await FallingEdge(clk)
    wire.value = 0
    valid.value = 0

@cocotb.test()
async def test_transmits(dut):
    """ a couple of values delivered, view waveform to confirm output"""
    dut.data_in.value = 0
    dut.valid_in.value = 0
    await cocotb.start( generate_clock(dut) )
    await reset(dut)

    await deliver_value(dut.clk_in, dut.valid_in, dut.ready_in, dut.data_in, 0x34)
    await Timer(10,units="ns")
    await deliver_value(dut.clk_in, dut.valid_in, dut.ready_in, dut.data_in, 0x77)
    await RisingEdge(dut.ready_in)
    await Timer(10,units="ns")
    await deliver_value(dut.clk_in,dut.valid_in,dut.ready_in,dut.data_in,0xFF)
    await RisingEdge(dut.ready_in)
    await Timer(50,units="ns")
