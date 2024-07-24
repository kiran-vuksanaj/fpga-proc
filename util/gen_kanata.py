import sys
import re

# PACKET_FIELD_LIST = [
#     # listed from lsb to msb
#     ("id_b",6,"MAINTAIN"),
#     ("checkpointB_en",1,"ZERO"),
#     ("id_a",6,"MAINTAIN"),
#     ("checkpointA_en",1,"ZERO"),
#     ("wen",1,"MAINTAIN"),
#     ("addr",27,"MAINTAIN"),
#     ("channel",3,"MAINTAIN"),
#     ("cycle",16,"SKIP")
#     ]

HEADER_FIELDS = [
    ("checkpoint_b_en",1),
    ("checkpoint_a_en",1),
    ("cycle_delay",14)
    ]
CHECKPOINT_A_FIELDS = [
    ("wen",1),
    ("addr",22),
    ("channel",3),
    ("id",6)
    ]
CHECKPOINT_B_FIELDS = [
    ("id",6),
    ("throwaway",2)
    ]


def unpack_vals(field_list,packed):
    """ Build dictionary of values selected from bits in an int value, according to field_list """
    out = {}
    for field_pair in field_list:
        name,length = field_pair
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


def file_bytes(f):
    out = []
    for line in f.readlines():
        hexbytes = re.findall('..',line)
        out.extend( reversed(hexbytes) )
    return out

def gen_kanata(tokens,kanatafile):
    """ from hex file probe input, generate a Konata-compliant log file to view pipelined data """
    
    with open(kanatafile,'w') as out:
        # write header
        out.write("Kanata\t0004\t\n")
        out.write("C=\t0\t\n")

        cycle = 0
        next_kid = 0

        job_kid = {}
        to_retire = []


        for token in tokens:
            if (len(to_retire) > 0):
                out.write("C\t1\t\n")
                for retiree in to_retire:
                    out.write("R\t{}\t{}\t\n".format(retiree,retiree))
                token['cycle_delay'] -= 1
            to_retire = []

            out.write("C\t{}\t\n".format(token['cycle_delay']))
            # out.write("C\t{}\t\n".format(1))
            if (token["checkpoint_a_en"] == 1):
                
                out.write("I\t{}\t{}\t{}\t\n".format(next_kid, token['checkpoint_a']['id'], token['checkpoint_a']['channel']))
                left_text = "@{:07x} channel={:d} wen={:b}".format( token['checkpoint_a']['addr'], token['checkpoint_a']["channel"], token['checkpoint_a']["wen"])
                
                out.write("L\t{}\t{}\t{}\t\n".format( next_kid, 1, left_text ))

                if (token['checkpoint_a']['wen'] == 1):
                    out.write("S\t{}\t{}\tWr\t\n".format( next_kid, 0 ))
                    to_retire.append(next_kid)
                else:
                    out.write("S\t{}\t{}\tRd\t\n".format( next_kid, 0))
                    job_kid[ token['checkpoint_a']['id'] ] = next_kid
                next_kid += 1

            if (token['checkpoint_b_en'] == 1):

                if ( token['checkpoint_b']['id'] in job_kid ):
                    kid = job_kid[ token['checkpoint_b']['id'] ]
                    out.write("S\t{}\t{}\tRs\t\n".format( kid, 0))
                    to_retire.append(kid)
                    


def parse_tokens(datums):
    tokens = []
    while datums:
        try:
            header_i = int(''.join(reversed([datums.pop(0) for i in range(2)])),16)
            header = unpack_vals(HEADER_FIELDS,header_i)
            print("H")
            print(header)
            assert(header['cycle_delay'] != 0)
            if (header['checkpoint_a_en'] == 0 and header['checkpoint_b_en'] == 0):
                print('idle')
                assert(header['cycle_delay'] == (1<<14)-1)
                
            if (header['checkpoint_a_en'] == 1):
                a_int = int( ''.join(reversed([datums.pop(0) for i in range(4)])), 16 )
                a = unpack_vals(CHECKPOINT_A_FIELDS,a_int)
                print("A")
                print(a)
                header['checkpoint_a'] = a
            if (header['checkpoint_b_en'] == 1):
                b_int = int( datums.pop(0), 16 )
                b = unpack_vals(CHECKPOINT_B_FIELDS,b_int)
                print("B")
                print(b)
                header['checkpoint_b'] = b
            tokens.append(header)
        except IndexError:
            print("final token broken")
    return tokens

if __name__ == "__main__":
    if (len(sys.argv) < 3):
        print("usage: {} [hexfile_input] [kanatafile_output]".format(sys.argv[0]))
        exit()
    # gen_kanata(sys.argv[1],sys.argv[2])
    with open (sys.argv[1]) as f:
        bytestrings = file_bytes(f)
        # print( "\n".join( tokens ) )
        messages = parse_tokens(bytestrings)
        # print(messages)
        gen_kanata(messages,sys.argv[2])
        
