import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

debug = False

def writemem(memory, addr, data):
    # data: bytearray, length 128 bits/16 bytes
    memory[addr] = data

def readmem(memory,addr):
    # returned 128 bit/16 byte bytearray
    if (addr in memory):
        return memory[addr]
    else:
        return 0xABABABABABABABABABABABABABABABAB.to_bytes(16,'big')

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

def command_assent(ready,valid):
    return (ready.value == 1 and valid.value == 1)

async def mimic_ready(clk,app_rdy,app_wdf_rdy):
    while True:
        await RisingEdge(clk)
        if (random.random() > 0.9):
            app_rdy.value = 0
            if (random.random() > 0.9):
                app_wdf_rdy.value = 0
            else:
                app_wdf_rdy.value = 1
        else:
            app_rdy.value = 1
            app_wdf_rdy.value = 1

async def generate_clock(clk):
    """ generate clock pulses """
    while True:
        clk.value = 0
        await Timer(5,units="ns")
        clk.value = 1
        await Timer(5,units="ns")

async def handle_request(dut,memory,responses):
    CMD_READ = 1
    CMD_WRITE = 0

    DELAY_NS = 100
    
    if (command_assent(dut.app_rdy,dut.app_en)):
        if (dut.app_cmd.value == CMD_READ):
            # READ cmd
            addr = int(dut.app_addr.value) >> 3
            await Timer(DELAY_NS,units="ns")
            read_data = readmem(memory,addr)
            # print(addr,read_data)
            responses.append( int.from_bytes(read_data,"big") )
            if (debug):
                print("[mig] read request @{:07x}".format(addr))
            return True
        else:
            # WRITE cmd
            if (command_assent(dut.app_wdf_rdy,dut.app_wdf_wren)):
                addr = int(dut.app_addr.value) >> 3
                data = int(dut.app_wdf_data.value).to_bytes(16,"big")
                writemem(memory,addr,data)
                if (debug):
                    print("[mig] write request @{:07x} [{:032x}]".format(addr,int.from_bytes(data,'big')))
                return True
            return False
    return False

async def deliver_responses(clk,valid,data,end,responses):
    while True:
        await RisingEdge(clk)
        if (len(responses) > 0):
            valid.value = 1
            end.value = 1
            resp = responses.pop(0)
            data.value = resp
            if (debug):
                print("[mig] response {:032x}".format(int(resp)))
        else:
            valid.value = 0
            end.value = 0

async def simulate_mig(dut,memory):
    dut.init_calib_complete.value = 0
    dut.app_sr_active.value = 0
    dut.app_ref_ack.value = 0
    dut.app_zq_ack.value = 0
    await cocotb.start( generate_clock(dut.ui_clk) )
    await Timer(10,units="ns")
    await cocotb.start( mimic_ready(dut.ui_clk, dut.app_rdy, dut.app_wdf_rdy) )
    await Timer(10,units="ns")
    dut.init_calib_complete.value = 1
    responses = []
    await cocotb.start( deliver_responses(dut.ui_clk, dut.app_rd_data_valid, dut.app_rd_data, dut.app_rd_data_end, responses) )

    while True:
        await RisingEdge(dut.ui_clk)
        await cocotb.start( handle_request(dut,memory,responses) )


@cocotb.test()
async def test_migsim(dut):
    """ python-level driving of mig simulator """

    memory = generate_memory('mem.vmh')
    await cocotb.start( simulate_mig(dut,memory) )
    dut.app_en.value = 0
    dut.app_wdf_wren.value = 0
    await Timer(30,units="ns")

    dut.app_en.value = 1
    dut.app_cmd.value = 1
    dut.app_addr.value = 0x200
    dut.app_wdf_wren.value = 1
    dut.app_wdf_data.value = 0x12341234ABABABABCDCDCDCD88888888
    await Timer(10,units="ns")

    dut.app_en.value = 0
    dut.app_wdf_wren.value = 0
    await Timer(40,units="ns")
    dut.app_en.value = 1
    dut.app_cmd.value = 0
    dut.app_addr.value = 0x100
    await Timer(10,units="ns")
    dut.app_addr.value = 0x200
    await Timer(10,units="ns")
    dut.app_en.value = 0
    await Timer(200,units="ns")

    for addr in memory:
        print("[{:07x}]: {:032x}".format(addr,int.from_bytes(memory[addr],"big")))
