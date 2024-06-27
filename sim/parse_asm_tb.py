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

def cmd_assent(ready,valid):
    return (ready.value == 1 and valid.value == 1)

async def print_axis_assents(dut):
    while True:
        await RisingEdge(dut.clk_in)
        if( cmd_assent( dut.axis_ready, dut.axis_valid ) ):
            print( "axis command: [%d]%032x" % (dut.axis_tuser.value, dut.axis_data.value) )

async def send_byte(dut,byte):
    dut.valid_fbyte.value = 1
    dut.fbyte.value = byte
    await Timer(10,units='ns')
    dut.valid_fbyte.value = 0
    cycles_wait = random.randint(2,5)
    await Timer(10*cycles_wait,units='ns')

def transmit_addr_print( addr ):
    print("@%x" % addr)

    
def transmit_chunk_print( chunk ):
    out_string = "["
    for i in range(4):
        word = chunk[3-i] if (3-i < len(chunk)) else 0
        out_string += "{:08x}".format(word)
    print(out_string)

async def write(dut,byteobject):
    # ser.write(byteobject)
    for byte in byteobject:
        await send_byte(dut,byte)
        # print("%02x" % byte)
    
async def transmit_addr(dut, addr ):
    symbol = "@".encode('utf-8')
    await write(dut, symbol)
    addr_bytes = addr.to_bytes(16, 'little')
    await write(dut, addr_bytes)
    # transmit_addr_print( addr )

async def transmit_chunk(dut, chunk ):
    symbol = "[".encode('utf-8')
    await write(dut, symbol)
    for i in range(4):
        word = chunk[i] if (i < len(chunk)) else 0
        word_bytes = word.to_bytes(4,'little')
        await write(dut, word_bytes)
    # transmit_chunk_print( chunk )
    

@cocotb.test()
async def test_with_file(dut):
    """ open mem.vmh and transmit the file to simulated parser """

    dut.axis_ready.value = 0
    dut.valid_fbyte.value = 0
    dut.fbyte.value = 0
    await cocotb.start( generate_clock(dut) )
    await reset(dut)
    await cocotb.start( print_axis_assents(dut) )
    dut.axis_ready.value = 1
    await Timer(20,units='ns')
    
    with open("mem.vmh",mode="r") as vmhfile:
        lines = vmhfile.readlines()
        current_index = 0
        current_chunk = []
        for line in lines:
            if '@' in line:
                print ("@ in line")
                if current_chunk:
                    await transmit_chunk(dut, current_chunk)
                    current_chunk = []
                    current_index = 0
                addr = int(line[1:].strip(),16)
                await transmit_addr( dut, addr )
            else:
                current_chunk.append( int(line.strip(), 16) )
                current_index = (current_index + 1) % 4
                if (current_index == 0):
                    await transmit_chunk(dut, current_chunk)
                    current_chunk = []
        if (current_chunk):
            await transmit_chunk(dut, current_chunk)
    
        

