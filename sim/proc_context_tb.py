import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

def write_memory(memory,current_addr,current_chunk):
    current_chunk.reverse()
    concatenated = bytearray()
    for piece in current_chunk:
        concatenated += piece
    # print( concatenated.hex() )
    memory[current_addr] = concatenated

def generate_memory(filename):
    memory = {}
    with open(filename,'r') as vmhfile:
        lines = vmhfile.readlines()
        current_index = 0
        current_chunk = []
        current_addr = 0
        for line in lines:
            if '@' in line:
                if current_chunk:
                    write_memory(memory,current_addr,current_chunk)
                    current_chunk = []
                    current_index = 0
                new_addr = int(line[1:].strip(),16) >> 2
                print("%x" % new_addr)
                current_addr = new_addr
            else:
                current_chunk.append( int(line.strip(), 16).to_bytes(4,'big') )
                current_index = (current_index + 1) % 4
                if (current_index == 0):
                    write_memory(memory, current_addr,current_chunk)
                    current_chunk = []
                    current_addr = current_addr + 1
        if (current_chunk):
            write_memory(memory, current_addr, current_chunk)
    # print(memory)
    return memory

async def generate_clock(clk):
    """ generate clock pulses """
    while True:
        clk.value = 0
        await Timer(5,units="ns")
        clk.value = 1
        await Timer(5,units="ns")

async def reset(reset):
    reset.value = 1
    await Timer(10,units="ns")
    reset.value = 0
    await Timer(10,units="ns")

async def reset_negedge(reset):
    reset.value = 0
    await Timer(10,units="ns")
    reset.value = 1
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

async def deliver_values(clk,valid,ready,wire,data_list):
    for value in data_list:
        value_int = int.from_bytes(value,'big')
        print("delivering %032x" % value_int)
        await deliver_value(clk,valid,ready,wire,value_int)
        await Timer(10,units="ns")
    print("[PY] delivery complete")

async def handle_mmio(dut):
    while True:
        await RisingEdge(dut.clk_in)
        if (dut.uart_tx_valid.value == 1):
            print("[PY] uart byte: %x" % dut.uart_tx_data.value)
        if (dut.processor_done == 1):
            print("[PY] EXIT")
            return True

async def handle_memory_requests(dut,memory):
    current_addr = 0
    current_wen = 1
    while (True):
        await RisingEdge(dut.clk_in)
        if ( cmd_assent(dut.req_axis_ready,dut.req_axis_valid) ):

            if (dut.req_axis_tuser.value == 1):
                req_data = dut.req_axis_data.value
                req_wen = req_data & 0x1 # bit 0
                stream_length = ((req_data >> 1) & 0x7FFFFFF) # bits 27:1
                req_addr = ((req_data >> 28) & 0x7FFFFFF) # bits 54:28
                
                current_addr = req_addr
                current_wen = req_wen
                print("[PY]request for addr 0x%x, length %d, wen=%d" % (req_addr,stream_length,req_wen))
                if (not req_wen):
                    resp_data_queue = []
                    for i in range(stream_length):
                        if ((req_addr+i) in memory):
                            resp_data_queue.append(memory[req_addr+i])
                        else:
                            resp_data_queue.append(bytes(4))
                    await cocotb.start( deliver_values(dut.clk_in,dut.resp_axis_valid,dut.resp_axis_ready,dut.resp_axis_data, resp_data_queue) )
            else:
                print("[PY]writing at 0x%x, data=%x" % (current_addr, dut.req_axis_data))
                memory[current_addr] = dut.req_axis_data
                current_addr += 1
        
    
            
@cocotb.test()
async def test_a(dut):
    """ give memory responses via python input """

    memory = generate_memory('mem.vmh')
    # for i in range(32):
    #     print("{:02x}: {}".format(i,memory[i].hex()))
    
    dut.req_axis_ready.value = 0
    dut.resp_axis_valid.value = 0
    dut.resp_axis_data.value = 0
    dut.resp_axis_tuser.value = 0
    dut.putMMIOResp_en.value = 0
    dut.uart_tx_ready.value = 1

    await cocotb.start( generate_clock(dut.clk_in) )
    await reset(dut.rst_in)

    dut.req_axis_ready.value = 1
    # await Timer(40000,units='ns')
    await cocotb.start( handle_memory_requests(dut,memory) )
    await handle_mmio(dut)

                
