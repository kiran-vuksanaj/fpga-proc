`timescale 1ns / 1ps
`default_nettype none

module core_tb;
   logic clk;
   logic rst;
   
   logic req_axis_ready;
   logic req_axis_valid;
   logic req_axis_tuser;
   logic [127:0] req_axis_data;

   logic resp_axis_ready;
   logic resp_axis_valid;
   logic resp_axis_tuser;
   logic [127:0] resp_axis_data;

   core_wrapper cwm
     (.clk_in(clk),
      .rst_in(rst),
      .req_axis_ready(req_axis_ready),
      .req_axis_valid(req_axis_valid),
      .req_axis_tuser(req_axis_tuser),
      .req_axis_data(req_axis_data),
      .resp_axis_ready(resp_axis_ready),
      .resp_axis_valid(resp_axis_valid),
      .resp_axis_tuser(resp_axis_tuser),
      .resp_axis_data(resp_axis_data));

   initial begin
      clk = 0;
   end
   always begin
      #5;
      clk = 1;
      #5;
      clk = 0;
   end

   initial begin
      $dumpfile("proc.vcd");
      $dumpvars(0,core_tb);
      
      rst = 1;
      #10;
      rst = 0;
      #30;
      req_axis_ready = 1;
      #200_000;
      $finish;
   end

endmodule

`default_nettype wire
