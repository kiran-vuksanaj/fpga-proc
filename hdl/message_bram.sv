`timescale 1ns / 1ps
`default_nettype none

module message_bram
  #(
    parameter PORT_WIDTH = 7, // IN BYTES!
    parameter BRAM_DEPTH = 1024
    )
  (
   input wire 			    clk_in,
   input wire 			    rst_in,
   input wire 			    en_in,

   input wire 			    valid_in,
   input wire [MSG_LENGTH-1:0] 	    length_in,
   input wire [PORT_WIDTH-1:0][7:0] data_in,

   output logic [BRAM_WIDTH-1:0]    bram_din,
   output logic 		    bram_we,
   output logic [BRAM_ADDR-1:0]     bram_addr
   );

   localparam BRAM_ADDR = $clog2(BRAM_DEPTH);
   localparam BRAM_WIDTH  = PORT_WIDTH*8;
   localparam MSG_LENGTH = $clog2(PORT_WIDTH);

   localparam STORE_WIDTH = PORT_WIDTH*2;
   localparam STORE_ADDR = $clog2(STORE_WIDTH);
   
   logic [STORE_WIDTH-1:0][7:0]     stored_bytes;
   logic [STORE_WIDTH-1:0][7:0]     stored_bytes_shift;
   logic [STORE_WIDTH-1:0][7:0]     stored_bytes_new;
   
   logic [STORE_WIDTH-1:0] 	    store_byte_en;
   
   logic [STORE_ADDR-1:0] 	    sb_index;
   logic [STORE_ADDR-1:0] 	    sb_index_hold;

   assign store_byte_en = ((1 << length_in) - 1) << sb_index;

   generate
      genvar 			    i;
      for( i = 0; i < STORE_WIDTH; i++ ) begin
	 assign stored_bytes_new[i] = (store_byte_en[i]) ? data_in[i-sb_index] : stored_bytes[i];
      end
   endgenerate

   assign stored_bytes_shift = { BRAM_WIDTH'(0), stored_bytes_new[STORE_WIDTH-1:PORT_WIDTH] };
   assign bram_we = valid_in && (sb_index + length_in >= PORT_WIDTH);
   assign bram_din = stored_bytes_new[PORT_WIDTH-1:0];
   
   always_ff @(posedge clk_in) begin
      if (rst_in || ~en_in) begin
	 sb_index <= 0;
	 stored_bytes <= 0;
	 bram_addr <= 0;
      end
      else begin
	 if (valid_in) begin
	    if (bram_we) begin
	       sb_index <= sb_index + length_in - PORT_WIDTH;
	       stored_bytes <= stored_bytes_shift;
	       bram_addr <= bram_addr + 1;
	    end
	    else begin
	       sb_index <= sb_index + length_in;
	       stored_bytes <= stored_bytes_new;
	    end
	 end
      end
   end

endmodule // message_bram

`default_nettype wire
