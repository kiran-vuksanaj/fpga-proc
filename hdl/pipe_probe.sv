`timescale 1ns / 1ps
`default_nettype none

`ifndef PARSED_META
`define PARSED_META
typedef struct packed {
   logic [2:0] channel;
   logic [26:0] addr;
   logic 	wen;
} parsed_meta;
`endif

typedef struct packed {
   logic [15:0] cycle_count;
   parsed_meta meta;
   logic 	checkpointA;
   logic [5:0] 	id_a;
   logic 	checkpointB;
   logic [5:0] 	id_b;
} bram_entry;


module pipe_probe #
  (parameter META_WIDTH = 31,
   parameter RAM_DEPTH = 1024)
  (
   input wire 		       rst_in,
   input wire 		       clk_in,

   input wire 		       probe_trigger_in,
   input wire 		       transmit_trigger_in,
   
   input wire [META_WIDTH-1:0] packet_meta,
   input wire 		       checkpointA_en,
   input wire [5:0] 	       id_a,
   input wire 		       checkpointB_en,
   input wire [5:0] 	       id_b,

   output logic [7:0] 	       uart_tx_data,
   input wire 		       uart_tx_ready,
   output logic 	       uart_tx_valid
   );

   localparam RAM_ADDR = $clog2(RAM_DEPTH);
   localparam BRAM_WIDTH = $bits(bram_entry);

   // activate probe with probe_trigger_in.
   // while probe is active, it waits for cycles where at least one checkpoint is active
   // (checkpointA_en or checkpointB_en)
   // and writes an entry to its BRAM.
   // once BRAM is full, or transmit_trigger_in is activated, data is transmitted 1 byte
   // at a time to the UART output.

   // Entry data: described in the 'bram_entry' struct above. its about 8 bytes long (right now)
   
   typedef enum 	       {IDLE,PROBE,TRANSMIT} probestate;
   probestate state;
      
   logic [31:0] 	       cycle_count;

   logic [RAM_ADDR-1:0]        ram_addr;
   logic [RAM_ADDR-1:0]        final_addr;
   logic [BRAM_WIDTH-1:0]      ram_din;
   logic 		       ram_wea;

   logic [BRAM_WIDTH-1:0]      ram_dout;
   
   xilinx_single_port_ram_read_first
     #(.RAM_WIDTH(BRAM_WIDTH),
      .RAM_DEPTH(RAM_DEPTH)) entry_bram
     (.addra(ram_addr),
      .dina(ram_din),
      .clka(clk_in),
      .wea(ram_wea),
      .ena(1'b1),
      .rsta(rst_in),
      .regcea(1'b1),
      .douta(ram_dout));
   

   parsed_meta meta;
   assign meta = packet_meta;

   logic 		       take_meta;
   assign take_meta = checkpointA_en;
   logic 		       write_entry;
   assign write_entry = (checkpointA_en || checkpointB_en);
   
   bram_entry entry_in;
   assign entry_in.cycle_count = cycle_count;
   assign entry_in.meta = take_meta ? meta : 'b0;
   assign entry_in.checkpointA = checkpointA_en;
   assign entry_in.id_a = (checkpointA_en) ? id_a : 'b0;
   assign entry_in.checkpointB = checkpointB_en;
   assign entry_in.id_b = (checkpointB_en) ? id_b : 'b0;

   assign ram_din = entry_in;

   assign ram_wea = (write_entry && state == PROBE);

   logic [7:0][7:0] 	       bytes;
   assign bytes = ram_dout;
   logic [2:0] 		       index;
   
   logic 		       wait_bram_cycle;
   assign uart_tx_valid = (~wait_bram_cycle && state == TRANSMIT);

   logic 		       accept_uart;
   assign accept_uart = (uart_tx_ready && uart_tx_valid);

   assign uart_tx_data = bytes[7-index];
			 
  always_ff @(posedge clk_in) begin
     if (rst_in) begin
	cycle_count <= 32'b0;
	state <= IDLE;
	ram_addr <= 'b0;
	index <= 3'b0;
	wait_bram_cycle <= 1'b1;
	final_addr <= 'b0;
     end
     else begin
	case(state)
	  IDLE: begin
	     
	     if (probe_trigger_in) begin
		cycle_count <= 32'b0;
		state <= PROBE;
	     end
	  end
	  PROBE: begin

	     cycle_count <= cycle_count + 1;

	     if (write_entry) begin
		ram_addr <= ram_addr + 1;
	     end
	     
	     if (checkpointA_en) begin
		$display("@[%08x] checkpointA : {channel %x, addr %x wen %b}",cycle_count,meta.channel,meta.addr,meta.wen);
	     end
	     if (checkpointB_en) begin
		$display("@[%08x] checkpointB",cycle_count);
	     end
	     
	     if ( (cycle_count+1) == 0 || (ram_addr+1 == 0) || (ram_addr+1 == RAM_DEPTH) || transmit_trigger_in ) begin
		state <= TRANSMIT;
		ram_addr <= 'b0;
		final_addr <= ram_addr;
		index <= 3'b0;
		wait_bram_cycle <= 1'b0;
	     end
	  end // case: PROBE
	  TRANSMIT: begin
	     if (wait_bram_cycle == 1'b1) begin
		wait_bram_cycle <= 1'b0;
	     end
	     else begin
		if( accept_uart ) begin
		   index <= index + 1;
		   if ( index == 7 ) begin
		      wait_bram_cycle <= 1'b1;
		      ram_addr <= ram_addr + 1;
		      if (ram_addr+1 == final_addr) state <= IDLE;
		   end
		end
	     end
	  end
	endcase
	
     end
  end

endmodule

`default_nettype wire

