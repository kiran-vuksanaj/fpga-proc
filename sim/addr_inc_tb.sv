`timescale 1ns / 1ps
	 
module addr_inc_tb;

   logic clk;
   logic rst;
   
   logic incr_in1;
   logic [5:0] addr_out1;

   cursor
     #(.WIDTH(6),
       .ROLLOVER(64),
       .RESET_VAL(24),
       .INCR_AMT(4)) aitm1
       (.clk_in(clk),
	.rst_in(rst),
	.incr_in(incr_in1),
	.cursor_out(addr_out1)
	);

   logic       incr_in2;
   logic [3:0] addr_out2;
   
   cursor
     #(.WIDTH(4),
       .ROLLOVER(11),
       .RESET_VAL(0)) aitm2
       (.clk_in(clk),
	.rst_in(rst),
	.incr_in(incr_in2),
	.cursor_out(addr_out2)
	);
   
      

   always begin
      #5;
      clk = ~clk;
   end
   initial begin
      clk = 0;
   end

   initial begin
      $dumpfile("fifo.vcd");
      $dumpvars(0, addr_inc_tb);


      $display("Starting sim");
      rst = 0;
      incr_in1 = 0;
      incr_in2 = 0;
      
      #16;

      rst = 1;
      #10;

      rst = 0;
      incr_in1 = 0;
      incr_in2 = 1;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      rst = 1;
      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      rst = 0;
      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      incr_in1 = 0;
      incr_in2 = 0;
      #10;

      incr_in1 = 0;
      incr_in2 = 0;
      #10;

      incr_in1 = 0;
      incr_in2 = 0;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;

      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      incr_in1 = 0;
      incr_in2 = 0;
      #10;
      
      incr_in1 = 1;
      incr_in2 = 1;
      #10;
      
      $finish;
      
   end

   

endmodule // fifo_tb
