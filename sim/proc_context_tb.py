import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

from mig import simulate_mig, generate_memory

async def reset(reset):
    """ single cycle high for the specified cocotb wire """
    reset.value = 1
    await Timer(10,units="ns")
    reset.value = 0
    await Timer(10,units="ns")

def cmd_assent(valid,ready):
    """ return whether an AXI-Stream value is being consumed, according to specified ready/valid wires """
    return (valid.value == 1 and ready.value == 1)

async def capture_bram(dut,memory):
    """ Monitor BRAM writes and store them in the `memory` dictionary """
    while True:
        await RisingEdge(dut.ui_clk)
        if (dut.probe.ram_wea.value == 1):
            addr = int(dut.probe.ram_addr.value)
            memory[addr] = int(dut.probe.ram_din.value)

async def handle_mmio(dut):
    """ listen for UART and processor_done outputs, print UART output and exit when program completes"""

    dut.mmio_uart_tx_ready.value = 1
    while True:
        await RisingEdge(dut.ui_clk)
        if (dut.mmio_uart_tx_valid.value == 1):
            value = dut.mmio_uart_tx_data.value
            dut.mmio_uart_tx_ready.value = 0
            # intentional delay to simulate UART operating on slower clock cycles
            await Timer(1000,units="ns")
            dut.mmio_uart_tx_ready.value = 1
            print("%c" % value,end="")
            # print("[PY] uart byte: %x" % dut.mmio_uart_tx_data.value)
        if (dut.processor_done == 1):
            print("[PY] EXIT")
            return True

PACKET_FIELD_LIST = [
    # listed from lsb to msb
    ("id_b",6,"MAINTAIN"),
    ("checkpointB_en",1,"ZERO"),
    ("id_a",6,"MAINTAIN"),
    ("checkpointA_en",1,"ZERO"),
    ("wen",1,"MAINTAIN"),
    ("addr",27,"MAINTAIN"),
    ("channel",3,"MAINTAIN"),
    ("cycle",16,"SKIP")
    ]

def unpack_vals(field_list,packed):
    """ Build dictionary of values selected from bits in an int value, according to field_list """
    out = {}
    for field_pair in field_list:
        name,length,mode = field_pair
        out[name] = packed & ((2**length)-1)
        packed = packed >> length
    return out

def print_probedata(full_packet):
    """ print fields of an entry_packet, and return the dictionary version of the fields """
    
    format_str = "\tcycle: {cycle:x}\n\tmeta.channel: {channel:b}\n\tmeta.addr: {addr:x}\n\tmeta.wen: {wen:b}\n\tchckpointA:{checkpointA_en:b} [{id_a:x}]\n\tcheckpointB:{checkpointB_en:b} [{id_b:x}]"
    
    components = unpack_vals(PACKET_FIELD_LIST,full_packet)
    
    print(format_str.format(**components))
    assert( components["checkpointB_en"]==1 or components["checkpointA_en"]==1 )
    return components
        
async def handle_probe(dut, memory,f):
    """ while pipe_probe is in `transmit` mode, write uart output to hex file, confirm it to match BRAM memory """
    receive_count = 0
    addr = 0
    dut.probe_uart_tx_ready.value = 1
    current_chunk = bytearray()

    while True:
        await RisingEdge(dut.ui_clk)
        if (dut.probe_uart_tx_valid.value == 1):
            value = int(dut.probe_uart_tx_data.value)
            dut.probe_uart_tx_ready.value = 0
            await Timer(1000,units="ns")
            dut.probe_uart_tx_ready.value = 1
            current_chunk.append( value )
            
            receive_count += 1
            if ((receive_count % 8) == 0):
                full_packet = int.from_bytes(current_chunk,'big')
                print("[@%03x] %016x" % (addr,full_packet) )
                f.write("%016x\n" % full_packet)
                f.flush()
                print_probedata(full_packet)
                assert( full_packet == memory[addr] )
                current_chunk = bytearray()
                addr += 1
            

        
@cocotb.test()
async def test_a(dut):
    """ test processor with instructions specified in mem.vmh, then save probe output to sim.hex """

    memory = generate_memory('mem.vmh')
    
    await cocotb.start( simulate_mig(dut,memory) )
    dut.rst_in.value = 0
    dut.probe_trigger.value = 0
    dut.transmit_trigger.value = 0
    dut.probe_uart_tx_ready.value = 0
    await Timer(10,units="ns")
    dut.rst_in.value = 1
    await Timer(30,units="ns")
    dut.rst_in.value = 0
    await Timer(10,units="ns")
    dut.probe_trigger.value = 1
    await Timer(10,units="ns")
    dut.probe_trigger.value = 0

    memory_bram = {}
    await cocotb.start( capture_bram(dut,memory_bram) )
    
    await handle_mmio(dut)

    await Timer(10,units="ns")
    dut.transmit_trigger.value = 1
    await Timer(10,units="ns")
    dut.transmit_trigger.value = 0

    with open("sim.hex","w") as f:
        await handle_probe(dut,memory_bram,f)

    

                
