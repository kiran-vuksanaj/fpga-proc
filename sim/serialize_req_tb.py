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

def pack_req(write,addr,data):
    return (write << 538) + (addr << 512) + data

async def print_successes(dut):
    while True:
        await RisingEdge(dut.clk_in)
        if (cmd_assent(dut.req_axis_ready,dut.req_axis_valid)):
            print("successful delivery at %dns, of data 0x%x and tuser %d"%(get_sim_time('ns'),dut.req_axis_data.value,dut.req_axis_tuser.value))
            

@cocotb.test()
async def test_a(dut):
    """ basic serializing test, ensure proper waveform behavior esp on ready/valids """
    dut.getMReq_en.value = 0
    dut.getMReq_data.value = 0
    dut.req_axis_ready.value = 0

    await cocotb.start( generate_clock(dut) )
    await reset(dut)
    await cocotb.start( print_successes(dut) )

    dut.req_axis_ready.value = 1
    await deliver_value(dut.clk_in,dut.getMReq_en,dut.getMReq_rdy,dut.getMReq_data, pack_req(1,0x304,0x1210))
    await Timer(30,units="ns")
    dut.req_axis_ready.value = 0
    await Timer(20,units="ns")
    dut.req_axis_ready.value = 1
    await Timer(30,units="ns")
    await deliver_value(dut.clk_in,dut.getMReq_en,dut.getMReq_rdy,dut.getMReq_data, pack_req(0,0x305,0))
    await Timer(50,units="ns")
