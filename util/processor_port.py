import serial
import sys

def transmit_addr_print( addr ):
    print("@%x" % addr)
    
def transmit_chunk_print( chunk ):
    out_string = "["
    for i in range(4):
        word = chunk[3-i] if (3-i < len(chunk)) else 0
        out_string += "{:08x}".format(word)
    print(out_string)

def write(byteobject,ser):
    ser.write(byteobject)
    # for byte in byteobject:
    #     print("%02x" % byte)
    
def transmit_addr( addr_full, ser ):
    symbol = "@".encode('utf-8')
    write(symbol,ser)
    addr = addr_full
    addr_bytes = addr.to_bytes(16, 'little')
    write(addr_bytes,ser)
    # transmit_addr_print( addr_full )
    # print("_")

def transmit_chunk( chunk, ser):
    symbol = "[".encode('utf-8')
    write(symbol,ser)
    for i in range(4):
        word = chunk[i] if (i < len(chunk)) else 0
        word_bytes = word.to_bytes(4,'little')
        write(word_bytes,ser)
    # transmit_chunk_print( chunk )
    # print("_")
    
def send_memfile(filename,ser):    
    with open(filename,mode="r") as vmhfile:
        lines = vmhfile.readlines()
        current_index = 0
        current_chunk = []
        for line in lines:
            if '@' in line:
                if current_chunk:
                    transmit_chunk(current_chunk,ser)
                    current_chunk = []
                    current_index = 0
                addr = int(line[1:].strip(),16)
                transmit_addr( addr , ser)
            else:
                current_chunk.append( int(line.strip(), 16) )
                current_index = (current_index + 1) % 4
                if (current_index == 0):
                    transmit_chunk(current_chunk,ser)
                    current_chunk = []
        if(current_chunk):
            transmit_chunk(current_chunk,ser)

def print_tty(ser):
    while True:
        char = ser.read().decode('utf-8')
        print(char,end="")
        if (char == '#'):
            val = int.from_bytes( ser.read(4), "little" )
            print("{:08x}".format(val),end="")

def write_tty(ser,filename):
    total = 0
    with open(filename,'wb') as f:
        while True:
            char = ser.read()
            f.write(char)
            total += 1
            if (total % 1000 == 0):
                print(total)

def print_probedata(full_packet):
    format_str = "\tcycle: {cycle:x}\n\tmeta.channel: {channel:b}\n\tmeta.addr: {addr:x}\n\tmeta.wen: {wen:b}\n\tchckpointA:{checkpointA:b} [{id_a:x}]\n\tcheckpointB:{checkpointB:b} [{id_b:x}]"
    components = {
        "id_b": (full_packet & 0x3F),
        "checkpointB": ((full_packet>>6) & 0x1),
        "id_a": ((full_packet>>7) & 0x3F),
        "checkpointA": ((full_packet >> 13) & 0x1),
        "wen": ((full_packet >> 14) & 0x1),
        "addr": ((full_packet >> 15) & 0x7FFFFFF),
        "channel": ((full_packet >> 42) & 0x7),
        "cycle": ((full_packet >> 45) & 0xFFFF)
        }
    
    print(format_str.format(**components))
    assert( components["checkpointB"]==1 or components["checkpointA"]==1 )
        
def handle_probe(ser,filename):
    receive_count = 0
    with open(filename,'w') as f:
        while True:
            entry_bytes = ser.read(8)
            entry = int.from_bytes(entry_bytes,'big')
            print("%016x"%entry)
            print_probedata(entry)
            f.write("{:016x}\n".format(entry))
        
        

if __name__ == "__main__":
    filename = sys.argv[1]
    
    ser = serial.Serial("/dev/ttyUSB1",57600)
    print("UART established")
    
    print("beginning file transmission")
    send_memfile(filename,ser)
    print("file transmitted")

    if (len(sys.argv) > 2):
        if (sys.argv[2] == "probe"):
            print("probe mode")
            handle_probe(ser,sys.argv[3])
        else:
            output_filename = sys.argv[2]
            print("writing output bytes to {}".format(output_filename))
            write_tty(ser,output_filename)
    else:
        print("listening for TTY output, writing to shell")
        print_tty(ser)



