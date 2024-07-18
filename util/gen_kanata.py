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
        
def gen_kanata(hexfile,kanatafile):
    """ from hex file probe input, generate a Konata-compliant log file to view pipelined data """
    
    with open(hexfile,'r') as in_hex, open(kanatafile,'w') as out:
        # write header
        out.write("Kanata\t0004\t\n")
        out.write("C=\t0\t\n")

        cycle = 0
        next_kid = 0

        job_kid = {}
        to_retire = []

        for line in in_hex.readlines():
            if (len(to_retire) > 0):
                out.write("C\t1\t\n")
                for retiree in to_retire:
                    out.write("R\t{}\t{}\t\n".format(retiree,retiree))
                cycle += 1
            to_retire = []

                
            packet = int(line,16)
            print(line.strip())
            packet = print_probedata(packet)

            new_cycle = packet['cycle']
            cycle_diff = new_cycle-cycle

            out.write("C\t{}\t\n".format(cycle_diff))
            # out.write("C\t{}\t\n".format(1))
            if (packet["checkpointA_en"] == 1):
                
                out.write("I\t{}\t{}\t{}\t\n".format(next_kid, packet["id_a"], packet["channel"]))
                left_text = "@{:07x} channel={:d} wen={:b}".format( packet["addr"], packet["channel"], packet["wen"])
                out.write("L\t{}\t{}\t{}\t\n".format( next_kid, 1, left_text ))

                if (packet["wen"] == 1):
                    out.write("S\t{}\t{}\tWr\t\n".format( next_kid, 0 ))
                    to_retire.append(next_kid)
                else:
                    out.write("S\t{}\t{}\tRd\t\n".format( next_kid, 0))
                    job_kid[ packet['id_a'] ] = next_kid
                next_kid += 1

            if (packet["checkpointB_en"] == 1):

                if ( packet['id_b'] in job_kid ):
                    kid = job_kid[ packet['id_b'] ]
                    out.write("S\t{}\t{}\tRs\t\n".format( kid, 0))
                    to_retire.append(kid)
                    

            cycle = new_cycle


if __name__ == "__main__":
    if (len(sys.argv) < 3):
        print("usage: {} [hexfile_input] [kanatafile_output]".format(sys.argv[0]))
        exit()
    gen_kanata(sys.argv[1],sys.argv[2])
        
