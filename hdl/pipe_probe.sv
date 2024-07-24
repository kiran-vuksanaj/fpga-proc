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
   localparam PORT_WIDTH = 7;
   localparam BRAM_WIDTH = PORT_WIDTH*8;

   // activate probe with probe_trigger_in.
   // while probe is active, it waits for cycles where at least one checkpoint is active
   // (checkpointA_en or checkpointB_en)
   // and writes an entry to its BRAM.
   // once BRAM is full, or transmit_trigger_in is activated, data is transmitted 1 byte
   // at a time to the UART output.

   
   typedef enum 	       {IDLE,PROBE,TRANSMIT} probestate;
   probestate state;
      

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

   logic [3:0] 		       length;
   logic [55:0] 	       message;
   logic 		       message_valid;
   
   probe_message pmm
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .checkpoint_a_en(checkpointA_en),
      .checkpoint_a_id(id_a),
      .checkpoint_a_meta(packet_meta),
      .checkpoint_b_en(checkpointB_en),
      .checkpoint_b_id(id_b),
      .message_length(length),
      .message_out(message),
      .message_valid(message_valid));

   logic [55:0] 	       message_din;
   logic [RAM_ADDR-1:0]        message_addr;
   logic 		       message_we;
   
   message_bram #(.PORT_WIDTH(PORT_WIDTH),.BRAM_DEPTH(RAM_DEPTH)) mbm
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .en_in( state == PROBE ),
      .valid_in(message_valid),
      .length_in(length),
      .data_in(message),
      .bram_din(message_din),
      .bram_we(message_we),
      .bram_addr(message_addr));

   logic [RAM_ADDR-1:0]        transmit_addr;
   
   always_comb begin
      case(state)
	IDLE: begin
	   ram_addr = 0;
	   ram_din = 0;
	   ram_wea = 0;
	end
	PROBE: begin
	   ram_addr = message_addr;
	   ram_wea = message_we;
	   ram_din = message_din;
	end
	TRANSMIT: begin
	   ram_addr = transmit_addr;
	   ram_din = 0;
	   ram_wea = 0;
	end
      endcase
   end // always_comb


   logic [1:0] wait_for_bram;
   logic accept_out;
   logic [3:0] index;

   logic [PORT_WIDTH-1:0][7:0] dout_bytes;
   assign dout_bytes = ram_dout;

   assign uart_tx_data = dout_bytes[index];
   assign accept_out = (uart_tx_ready && uart_tx_valid);
   assign uart_tx_valid = (state == TRANSMIT && wait_for_bram == 0);
   
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 state <= IDLE;
	 transmit_addr <= 0;
	 wait_for_bram <= 1'b1;
	 index <= 0;
	 final_addr <= 0;
      end else begin
	 case(state)
	   IDLE: begin
	      if (probe_trigger_in) state <= PROBE;
	   end
	   PROBE: begin
	      if (ram_addr + 1 == 0 || ram_addr + 1 == RAM_DEPTH || transmit_trigger_in) begin
		 state <= TRANSMIT;
		 transmit_addr <= 0;
		 wait_for_bram <= 2'd2;
		 index <= 0;
		 final_addr <= ram_addr;
		 
	      end
	   end
	   TRANSMIT: begin
	      if (wait_for_bram > 0) begin
		 wait_for_bram <= wait_for_bram - 1;
	      end else begin
		 if (accept_out) begin
		    if (index < PORT_WIDTH-1) begin
		       $display("transmitted %02x [%d] %012x",uart_tx_data,index,dout_bytes);
		       index <= index + 1;
		    end
		    else begin
		       index <= 0;
		       if (transmit_addr + 1 == RAM_DEPTH || transmit_addr + 1 == 0 || transmit_addr + 1 == final_addr) begin
			  state <= IDLE;
		       end
		       else begin
			  transmit_addr <= transmit_addr + 1;
			  wait_for_bram <= 1'b1;
		       end
		    end
		 end
	      end
	   end
	 endcase
      end
   end


endmodule

`default_nettype wire

