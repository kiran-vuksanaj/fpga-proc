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

def write_tty(ser):
    total = 0
    with open('dithered.p4','wb') as f:
        while total < (1280*720/8):
            char = ser.read()
            f.write(char)
            total += 1
            if (total % 1000 == 0):
                print(total)
        

if __name__ == "__main__":
    filename = sys.argv[1]
    
    ser = serial.Serial("/dev/ttyUSB1",57600)
    print("UART established")
    
    print("beginning file transmission")
    send_memfile(filename,ser)
    print("file transmitted")

    print("listening for putchar TTY output")
    # print_tty(ser)
    write_tty(ser)


