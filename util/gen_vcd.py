from vcd.writer import VCDWriter
import sys

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
        
def gen_vcd(hexfile,vcdfile):
    """ from hex file probe output, generate a VCD waveform file """

    with open(hexfile,'r') as in_hex, VCDWriter(open(vcdfile,'w')) as writer:
        vcd_wires = {}
        for field in PACKET_FIELD_LIST:
            name,length,mode = field
            if (mode != "SKIP"):
                vcd_wires[ name ] = writer.register_var('capture',name,'wire',length)
        
        clk = writer.register_var('capture','clk','wire',1)
        clk_cycle = 0
        for line in in_hex.readlines():
            packet = int(line,16)
            print(line.strip())
            components = print_probedata(packet)
            cycle = components["cycle"]
            
            while (clk_cycle < cycle):
                for field in PACKET_FIELD_LIST:
                    name,length,mode = field
                    if (mode == "ZERO"):
                        writer.change( vcd_wires[name] , 10*clk_cycle, 0 )
                writer.change(clk, 10*clk_cycle, 1)
                writer.change(clk, 10*clk_cycle+5, 0)
                clk_cycle += 1

            writer.change(clk, 10*cycle, 1)
            for field in PACKET_FIELD_LIST:
                name,length,mode = field
                if (mode != "SKIP"):
                    writer.change( vcd_wires[name], 10*cycle, components[name] )
                
            writer.change(clk, 10*cycle + 5, 0)
            clk_cycle += 1





if __name__ == "__main__":
    if (len(sys.argv) < 3):
        print("usage: {} [hexfile_input] [vcdfile_output]".format(sys.argv[0]))
        exit()
    gen_vcd(sys.argv[1],sys.argv[2])
