`timescale 1ns / 1ps
`default_nettype none

`ifndef CHANNEL_UPDATE
 `define CHANNEL_UPDATE
typedef struct packed {
   logic [26:0] addr;
   logic [26:0] stream_length;
   logic 	wen;
} channel_update;
`endif

module parse_asm
  (
   input wire 		clk_in,
   input wire 		rst_in,
   input wire 		valid_fbyte,
   input wire [7:0] 	fbyte,
   
   output logic 	axis_tuser,
   output logic [127:0] axis_data,
   input wire 		axis_ready,
   output logic 	axis_valid);

   typedef enum 	{ASC,CHUNK} linestate;
   linestate lstate;
   
   typedef enum 	{ADDR,DATA} filestate;
   filestate fstate;
   
   logic [3:0] 		byte_index;
   logic [7:0] 		axis_bytes [15:0];
   logic [127:0] 	axis_data_chunk;

   assign axis_data_chunk = {axis_bytes[15],
			     axis_bytes[14],
			     axis_bytes[13],
			     axis_bytes[12],
			     axis_bytes[11],
			     axis_bytes[10],
			     axis_bytes[9],
			     axis_bytes[8],
			     axis_bytes[7],
			     axis_bytes[6],
			     axis_bytes[5],
			     axis_bytes[4],
			     axis_bytes[3],
			     axis_bytes[2],
			     axis_bytes[1],
			     axis_bytes[0]};

   channel_update command;
   assign command.addr = axis_data_chunk[26:0] >> 2;
   assign command.stream_length = 27'b0;
   assign command.wen = 1'b1;

   assign axis_tuser = (fstate == ADDR);
   assign axis_data = axis_tuser ? command : axis_data_chunk;
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 lstate <= ASC;
	 fstate <= ADDR;
	 byte_index <= 0;
	 axis_valid <= 0;
      end
      else if (valid_fbyte) begin
	 case (lstate)
	   ASC: begin
	      fstate <= (fbyte == 8'h40) ? ADDR : DATA;
	      lstate <= CHUNK;
	      byte_index <= 0;
	   end
	   CHUNK: begin
	      axis_bytes[byte_index] <= fbyte;
	      byte_index <= byte_index + 1;
	      if (byte_index == 15) begin
		 axis_valid <= 1;
		 lstate <= ASC;
	      end
	   end
	 endcase
      end // if (valid_fbyte)
      if (axis_valid) begin
	 axis_valid <= ~axis_ready;
      end
      if (axis_tuser && axis_valid) begin
	 $display("addr: %x",command.addr);
      end
   end
	 
      


endmodule
   
   
`default_nettype wire
