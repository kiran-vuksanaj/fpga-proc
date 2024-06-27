`timescale 1ns / 1ps
`default_nettype none

module build_wr_data
   (
    input wire 		 clk_in,
    input wire 		 rst_in,
    // input axis: 8 bit samples
    input wire 		 valid_in,
    output logic 	 ready_in,
    input wire [7:0] 	 data_in,
    input wire 		 newframe_in,
    // output axis: 128 bit mig-phrases
    output logic 	 valid_out,
    input wire 		 ready_out,
    output logic [127:0] data_out,
    output logic 	 tuser_out
    );

   logic [7:0] 		 words [15:0]; // unpacked version of data_out
   logic 		 accept_in;
   logic [3:0] 		 offset;
   logic 		 offset_rollover;
   logic 		 phrase_taken;
      
   assign data_out = {words[0],
		      words[1],
		      words[2],
		      words[3],
		      words[4],
		      words[5],
		      words[6],
		      words[7],
		      words[8],
		      words[9],
		      words[10],
		      words[11],
		      words[12],
		      words[13],
		      words[14],
		      words[15]};

   cursor #(.ROLLOVER(16)) aio
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .incr_in(accept_in),
      .cursor_out(offset),
      .rollover_out(offset_rollover));

   assign ready_in = phrase_taken;
   assign accept_in = ready_in && valid_in;
   assign valid_out = (offset_rollover) || ~phrase_taken;
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 phrase_taken <= 1'b1;
	 tuser_out <= 1'b0;
      end else begin
	 if (accept_in) begin
	    // write data to proper section of phrasedata
	    words[offset] <= data_in;
	    tuser_out <= (offset == 0) ? newframe_in : (newframe_in || tuser_out);
	 end
	 if (offset == 15 || ~phrase_taken) begin
	    phrase_taken <= ready_out;
	 end
      end
   end
   
endmodule // build_wr_data

module digest_phrase
  (
   input wire 	      clk_in,
   input wire 	      rst_in,
   // input axis: 128 bit phrases
   input wire 	      valid_phrase,
   output logic       ready_phrase,
   input wire [127:0] phrase_data,
   input wire 	      phrase_tuser,
   // output axis: 8 bit words
   output logic       valid_word,
   input wire 	      ready_word,
   output logic [7:0] word,
   output logic       newframe_out
   );

   // IMPORTANT NOTE
   // newframe_out can be checked whenever valid_word is asserted, /regardless/ of if ready_word is high.
   // user can check whether the /next/ data will be the newframe data, without consuming it!

   logic [3:0] 	       offset;
   cursor #(.ROLLOVER(16)) aio
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .incr_in( ready_word && valid_word ),
      .cursor_out(offset));

   logic [127:0]       phrase;
   logic 	       tuser;
   logic [7:0] 	       words[15:0]; // unpacked phrase
   assign words[15] = phrase[7:0];
   assign words[14] = phrase[15:8];
   assign words[13] = phrase[23:16];
   assign words[12] = phrase[31:24];
   assign words[11] = phrase[39:32];
   assign words[10] = phrase[47:40];
   assign words[9] = phrase[55:48];
   assign words[8] = phrase[63:56];
   assign words[7] = phrase[71:64];
   assign words[6] = phrase[79:72];
   assign words[5] = phrase[87:80];
   assign words[4] = phrase[95:88];
   assign words[3] = phrase[103:96];
   assign words[2] = phrase[111:104];
   assign words[1] = phrase[119:112];
   assign words[0] = phrase[127:120];

   logic 	       needphrase;
   
   assign valid_word = ~needphrase; // lock output + keep offset=0 while
   
   assign ready_phrase = ((offset == 15) && ready_word) ||
			 ((offset == 0) && needphrase);
   
   assign word = words[offset];
   assign newframe_out = valid_word && (offset == 0) && tuser;
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 phrase <= 128'b0;
	 needphrase <= 1'b1;
      end else begin
	 if (ready_phrase) begin
	    if (valid_phrase) begin
	       needphrase <= 1'b0;
	       phrase <= phrase_data;
	       tuser <= phrase_tuser;
	    end else begin
	       needphrase <= 1'b1;
	    end
	 end
      end
   end
   
endmodule   

`default_nettype wire
