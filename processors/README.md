### Link processor into design

1. create directory of Verilog/SystemVerilog RTL files describing processor design
   * the "top level" of it should be a module called `wrapped_processor`, with ports for the AXI-Stream requests to memory, responses from memory, UART output, and done signal
2. in the `hdl/` directory, create a symlink: `ln -s ../processors/<design_name>/ proc`
3. Run build script like normal
