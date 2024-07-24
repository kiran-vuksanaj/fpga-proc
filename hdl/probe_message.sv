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
   logic [13:0] cycle_delay;
   logic       a_en;
   logic       b_en;
} header_byte;

typedef struct packed {
   logic [5:0] id;
   logic [2:0] channel;
   logic [21:0] addr;
   logic 	wen;
} checkpoint_a;

typedef struct packed {
   logic [1:0] throwaway;
   logic [5:0] id;
} checkpoint_b;


module probe_message
  (
   input wire 	       clk_in,
   input wire 	       rst_in,
   
   input wire 	       checkpoint_a_en,
   input wire [5:0]    checkpoint_a_id,
   input wire [30:0]   checkpoint_a_meta,
   
   input wire 	       checkpoint_b_en,
   input wire [5:0]    checkpoint_b_id,

   output logic [3:0]  message_length,
   output logic [55:0] message_out,
   output logic        message_valid
   
   );

   logic [13:0] 	       cycle_delay;

   header_byte message_header;
   assign message_header.cycle_delay = cycle_delay;
   assign message_header.a_en = checkpoint_a_en;
   assign message_header.b_en = checkpoint_b_en;

   parsed_meta meta_a;
   assign meta_a = checkpoint_a_meta;
   
   checkpoint_a message_a;
   assign message_a.id = checkpoint_a_id;
   assign message_a.channel = meta_a.channel;
   assign message_a.addr = meta_a.addr[24:3];
   assign message_a.wen = meta_a.wen;

   checkpoint_b message_b;
   assign message_b.throwaway = 2'b0;
   assign message_b.id = checkpoint_b_id;

   
   always_comb begin
     case( {message_header.a_en, message_header.b_en} )
       2'b00: begin
	  message_length = 2;
	  message_out = { 40'b0, message_header };
       end
       2'b01: begin
	  message_length = 3;
	  message_out = {32'b0, message_b, message_header};
       end
       2'b10: begin
	  message_length = 6;
	  message_out = {8'b0, message_a, message_header};
       end
       2'b11: begin
	  message_length = 7;
	  message_out = {message_b, message_a, message_header};
       end
     endcase // case ( {message_header.a_en, message_header.b_en} )
   end // always_comb

   assign message_valid = (checkpoint_a_en || checkpoint_b_en || cycle_delay == (1<<14)-1);

   always_ff @(posedge clk_in) begin
      if (rst_in || message_valid) begin
	 cycle_delay <= 1;
      end else begin
	 cycle_delay <= cycle_delay + 1;
      end
   end
   

endmodule // probe_message

`default_nettype wire

		      
