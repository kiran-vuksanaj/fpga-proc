import cocotb
from cocotb.triggers import RisingEdge, Timer, FallingEdge
from cocotb.utils import get_sim_time
import random

CMD_READ = 1
CMD_WRITE = 0
CHANNEL_COUNT = 3

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


async def print_mig_commands_issued(dut):
    while True:
        await RisingEdge(dut.clk_in)
        for i in range(CHANNEL_COUNT):
            if (dut.write_axis_valid[i].value == 1 and dut.write_axis_ready[i].value == 1):
                print("merger received command on channel %d: tuser = %d, data = %x" % (i, dut.write_axis_tuser[i].value, dut.write_axis_data[i].value))

def cmd_assent(dut):
    return (dut.app_en.value == 1 and dut.app_rdy.value == 1) # and
            # ( dut.app_cmd.value == CMD_READ or (dut.app_cmd.value == CMD_WRITE and dut.app_wdf_wren.value == 1 and dut.app_wdf_rdy.value == 1) ) )

async def simulate_mig_ready(dut):
    while True:
        await RisingEdge(dut.clk_in)
        if (random.random() > 0): # 0.3
            dut.app_rdy.value = 1
            if (random.random() > 0): # 0.2
                dut.app_wdf_rdy.value = 1
            else:
                dut.app_wdf_rdy.value = 0
        else:
            dut.app_rdy.value = 0
            dut.app_wdf_rdy.value = 0

async def simulate_mig_readresponses(dut):
    total_reads = 0
    while True:
        await RisingEdge(dut.clk_in)
        if (cmd_assent(dut) and dut.app_cmd.value == CMD_READ):
            total_reads += 1
        if (random.random() > 0.4 and total_reads > 0):
            total_reads -= 1
            dut.app_rd_data_valid.value = 1
            dut.app_rd_data_end.value = 1
            dut.app_rd_data.value = 3290
        else:
            dut.app_rd_data_valid.value = 0
            dut.app_rd_data_end.value = 0
            dut.app_rd_data.value = 0
            
async def print_mig_commands_received(dut):
    while True: 
        await RisingEdge(dut.clk_in)
        if (cmd_assent(dut)):
            if (dut.app_cmd.value == CMD_READ):
                print("MIG received READ command (@%dns): addr = %x" % (get_sim_time('ns'),dut.app_addr.value))
            elif (dut.app_cmd.value == CMD_WRITE):
                print("MIG received WRITE command (@%dns): addr = %x, data = %x" % (get_sim_time('ns'), dut.app_addr.value>>7, dut.app_wdf_data.value))

async def submit_data(dut,channel,data,tuser=0):
    # await FallingEdge(dut.clk_in)
    dut.write_axis_valid[channel].value = 1
    dut.write_axis_tuser[channel].value = tuser
    dut.write_axis_data[channel].value = data
    # print("submitting data %x @%dns" % (data, get_sim_time('ns')))
    await RisingEdge(dut.clk_in)
    while(dut.write_axis_ready[channel].value == 0):
        await Timer(10,units="ns")
    await FallingEdge(dut.clk_in)
    # print('done sime time %dns' % get_sim_time('ns'))
    dut.write_axis_valid[channel].value = 0
    dut.write_axis_tuser[channel].value = 0
    dut.write_axis_data[channel].value = 0
    # await RisingEdge(dut.clk_in)

@cocotb.test()
async def test_a(dut):
    """ randomized ready signal, randomized read responses, a few basic requests issued """
    # set input wires
    dut.app_sr_active.value = 1
    dut.app_ref_ack.value = 1
    dut.app_zq_ack.value = 1
    dut.init_calib_complete.value = 0

    await cocotb.start( generate_clock(dut) )
    await reset(dut)

    await cocotb.start(print_mig_commands_issued(dut))
    await cocotb.start(simulate_mig_ready(dut))
    await cocotb.start(simulate_mig_readresponses(dut))
    await cocotb.start(print_mig_commands_received(dut))

    for i in range(CHANNEL_COUNT):
        dut.write_axis_data[i].value = 0
        dut.write_axis_tuser[i].value = 0
        dut.write_axis_valid[i].value = 0
        dut.write_axis_smallpile[i].value = 0
        dut.read_axis_ready[i].value = 1
        dut.read_axis_af[i].value = 0
    await Timer(20,units="ns")
    dut.init_calib_complete.value = 1
    await RisingEdge(dut.clk_in)
    command_val = (0x443 << 28) + (0x10 << 1) + 1
    await submit_data(dut,1,command_val,tuser=1)
    await submit_data(dut,1,0x1234)
    await submit_data(dut,1,0x3922)
    # read command restricted by target addr
    command_val = (0x111 << 28) + (0x10 << 1) + 0
    await submit_data(dut,0,command_val,tuser=1)
    await Timer(400,units="ns")


@cocotb.test()
async def test_looping_read(dut):
    """ randomized ready signal, randomized read responses, read value set continuous valid """
    # set input wires
    dut.app_sr_active.value = 1
    dut.app_ref_ack.value = 1
    dut.app_zq_ack.value = 1
    dut.init_calib_complete.value = 0
    for i in range(CHANNEL_COUNT):
        dut.write_axis_data[i].value = 0
        dut.write_axis_tuser[i].value = 0
        dut.write_axis_valid[i].value = 0
        dut.write_axis_smallpile[i].value = 0
        dut.read_axis_ready[i].value = 1
        dut.read_axis_af[i].value = 0

    await cocotb.start( generate_clock(dut) )
    await reset(dut)

    await cocotb.start(print_mig_commands_issued(dut))
    await cocotb.start(simulate_mig_ready(dut))
    await cocotb.start(simulate_mig_readresponses(dut))
    await cocotb.start(print_mig_commands_received(dut))

    await Timer(20,units="ns")
    dut.init_calib_complete.value = 1

    await RisingEdge(dut.clk_in)
    command_val = (0x111 << 28) + (0x12 << 1) + 0
    dut.write_axis_data[i].value = command_val
    dut.write_axis_tuser[i].value = 1
    dut.write_axis_valid[i].value = 1

    await Timer(1000,units="ns")

    
@cocotb.test()
async def test_camera_read(dut):
    """simulate conditions of the camera input/output setup"""
    
