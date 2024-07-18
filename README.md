# NEW STUFF: ila probe
* `hdl/pipe_probe.sv`: Module for capturing probe data, writing it to BRAM
  * Example instantiations exist in `hdl/top_level.sv` and `sim/memorytb_top.sv`
* `util/processor_port.py <hexfile> probe <probe_output>`; run processor, then capture probe data
* `sim/mig.py`: CocoTB methods to simply simulate MIG interactions
* `sim/proc_context_tb.py`: run processor, and capture probe data

* `python3 util/gen_vcd.py <hexfile> <vcdfile>` builds waveform from probe output
* `python3 util/gen_kanata.py <hexfile> <output>.log` builds "Kanata" format for

* `sw[2]`: When on, UART output comes from probe. When off, UART output comes from processor.

### Konata logging
* I've been using [Konata](https://github.com/shioyadan/Konata), a tool typically used for visualing pipelined processors, and generating kanata logs (the [format](https://github.com/shioyadan/Konata/blob/master/docs/kanata-log-format.md) specified for the tool) but just setting the "pipeline stages" to be relevant to the probe data I have (write commands, read commands, read responses). It's a very nice way to be able to display pipelined data, dead cycles, etc.

### How-To: Probe in Simulation
* `cd sim/`
* `make`: runs the `proc_context_tb` cocotb tests, running the processor with the `mem.vmh` instructions, and generates the probe output at `sim.hex`
* to get a VCD file: `python3 util/gen_vcd.py sim/sim.hex capture.vcd`
* to get a Konata-format log: `python3 util/gen_kanata.py sim/sim.hex capture.log`

### How-To: Probe on Fabric
* build script like normal
* load to board
* set `sw[2]` to high: capture probe output instead of processor output
* `python3 util/processor_port.py util/hex/hello.hex probe capture.mem`: Load "Hello World" into processor, prepare for probe output
* Press `btn[2]` to start processor and trigger probe
* `^C` to escape python script
* to get a VCD file: `python3 util/gen_vcd.py capture.mem capture.vcd`
* to get a Konata-format log: `python3 util/gen_kanata.py capture.mem capture.log`

# Processor + Camera interaction

### prerequisites
* Vivado
* openFPGALoader
* python `pyserial`
* An image viewer that can open `.p4` (PBM) image files

### interactions

* `sw[0]`: Freeze frame
* `sw[1]`: Mode of HDMI interpreter (off is grayscale, on is RGB)

* `btn[0]`: Reset
* `btn[1]`: Configure Camera
* `btn[2]`: Init Processor

* `led[0]`: proc_reset :: if on, processor is currently disabled and at pc=0
* `led[1]`: debug_epoch :: current epoch of processor
* `led[2]`: init\_calib\_complete: if on, the DDR memory is ready to be used
* `led[3]`: processor_done :: processor sent an MMIO exit() signal

* `python3 util/processor_port.py [hexfile]` :: send hex file assembly to processor, wait for response values over UART and print them to shell
* `python3 util/processor_port.py [hexfile] p4` :: send hex file assembly to processor, interpret responses as an image file and write it to `dithered.p4`
  * if the UART port won't open, change the port value to the correct value for how your devboard is connected.
  
### example dithering
* `vivado -mode batch -source build.tcl` (build takes me around 5-6 minutes)
* turn on devboard, with camera adapter and camera attached to PMODs and monitor attached to HDMI
* `openFPGALoader -b arty_s7_50 obj/final.bit`
* press `btn[1]` to initialize camera registers
* set `sw[1:0]` to `10` to view live image output
* switch `sw[0]` off to freeze output
* switch `sw[1]` off to interpret image as grayscale (it'll look wrong right now)
* from computer: `python3 util/processor_port.py util/hex/dither32.hex dither.p4`
* press `btn[2]` to initialize processor
* watch corrected grayscale load in, and then dithered image load in to HDMI output. watch for counter values getting printed to shell once dithering is complete and transmitting begins.
* when `btn[3]` turns on and the counter values stop printing, exit the python script with `^C`
* use `open dither.p4` (ImageMagick) or your image viewer of choice that displays PBM images to view results on your computer!
* To do it again: switch off and on the "freeze frame" `sw[0]`, and reset the processor with `btn[0]`. Then, Send a new hex file and initialize processor like normal.
