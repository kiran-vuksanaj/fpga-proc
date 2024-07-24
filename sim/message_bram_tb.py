import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random


async def capture_bram(clk,we,addr,din,memory):
    """ Monitor BRAM writes and store them in the `memory` dictionary """
    while True:
        await RisingEdge(clk)
        if (we.value == 1):
            addr_val = int(addr.value)
            memory[addr_val] = int(din.value)
            print("[bram] write @({:x}) = {:x}".format(addr_val,memory[addr_val]))

async def reset(reset):
    """ single cycle high for the specified cocotb wire """
    reset.value = 1
    await Timer(10,units="ns")
    reset.value = 0
    await Timer(10,units="ns")

async def generate_clock(clk):
    """ generate clock pulses """
    while True:
        clk.value = 0
        await Timer(5,units="ns")
        clk.value = 1
        await Timer(5,units="ns")

def sel_bits(n,lo,hi):
    length = hi-lo
    byte_en = (1 << length) - 1
    return (n >> lo) & byte_en
        
def test_memory(memory,byte_sequence):
    for i in range(len(byte_sequence)):
        memory_addr = i // 7
        memory_offset = i % 7
        if (len(byte_sequence) - memory_addr*7 >= 7):
            memory_data = memory[memory_addr]
            memory_byte = sel_bits(memory_data,memory_offset*8,(memory_offset+1)*8)
            print("dut: 0x{:x} test: 0x{:x}".format(memory_byte,byte_sequence[i]))
            assert( memory_byte == byte_sequence[i] )

async def deliver_values(dut,byte_sequence,values):
    dut.valid_in.value = 1

    byte_values = bytearray( values )

    concat_bytes = int.from_bytes(byte_values,'big')
    print("concat: 0x{:x}".format(concat_bytes))

    dut.data_in.value = concat_bytes
    dut.length_in.value = len(values)

    byte_sequence.extend(reversed(values))
    
    await Timer(10,units="ns")
    dut.valid_in.value = 0

@cocotb.test()
async def test_mb(dut):
    """ throw some basic messages of varying lengths into message_bram """

    await cocotb.start( generate_clock(dut.clk_in) )
    dut.valid_in.value = 0
    dut.length_in.value = 0
    dut.data_in.value = 0
    await reset( dut.rst_in )
    memory = {}
    byte_sequence = []
    await cocotb.start( capture_bram(dut.clk_in, dut.bram_we, dut.bram_addr, dut.bram_din, memory) )

    await deliver_values(dut,byte_sequence, [0x11,0x22,0x33,0x44,0x55,0x66,0x77])

    await deliver_values(dut,byte_sequence, [])
    await deliver_values(dut,byte_sequence, [0xaa,0xbb])
    await deliver_values(dut,byte_sequence, [0x99])
    await deliver_values(dut,byte_sequence, [0x12, 0x23, 0x34, 0x45, 0x66])

    await deliver_values(dut,byte_sequence, [0x00,0x00,0x00,0x00,0x00,0x00,0x00])

    await Timer(100,units="ns")
    test_memory(memory,byte_sequence)
