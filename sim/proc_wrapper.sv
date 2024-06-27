`timescale 1ns / 1ps
`default_nettype none

module core_wrapper
  (
   input wire 		clk_in,
   input wire 		rst_in,
   input wire 		req_axis_ready,
   output logic 	req_axis_valid,
   output logic 	req_axis_tuser,
   output logic [127:0] req_axis_data,
   output logic 	resp_axis_ready,
   input wire 		resp_axis_valid,
   input wire 		resp_axis_tuser,
   input wire [127:0] 	resp_axis_data,

   output logic [7:0] 	uart_tx_data,
   input wire 		uart_tx_ready,
   output logic 	uart_tx_valid,

   output logic processor_done
   );

   logic 	       getMReq_en;
   logic 	       getMReq_rdy;
   logic [538:0]       getMReq_data;

   logic 	       getMMIOReq_en;
   logic 	       getMMIOReq_rdy;
   logic [67:0]	       getMMIOReq_data;

   logic 	       putMMIOResp_en;
   logic 	       putMMIOResp_rdy;
   logic [67:0]        putMMIOResp_data;
   
   logic 	       putMResp_en;
   logic 	       putMResp_rdy;
   logic [511:0]       putMResp_data;
   
   handle_mmio hmm
     (.clk_in(clk_in),
      .rst_in(rst_in),
      
      .getMMIOReq_en(getMMIOReq_en),
      .getMMIOReq_rdy(getMMIOReq_rdy),
      .getMMIOReq_data(getMMIOReq_data),

      .putMMIOResp_en(putMMIOResp_en),
      .putMMIOResp_rdy(putMMIOResp_rdy),
      .putMMIOResp_data(putMMIOResp_data),

      .uart_tx_data(uart_tx_data),
      .uart_tx_ready(uart_tx_ready),
      .uart_tx_valid(uart_tx_valid),

      .processor_done(processor_done));
   
   
   // logic [31:0]        debug_fetch_nextPc;

   mkProcCore processor
     (.CLK(clk_in),
      .RST_N(~rst_in), // reset active low, i think by default
      // .debug_fetch_nextPc(debug_fetch_nextPc),

      .EN_getMReq(getMReq_en),
      .getMReq(getMReq_data),
      .RDY_getMReq(getMReq_rdy),

      .putMResp_data(putMResp_data),
      .EN_putMResp(putMResp_en),
      .RDY_putMResp(putMResp_rdy),

      .EN_getMMIOReq(getMMIOReq_en),
      .getMMIOReq(getMMIOReq_data),
      .RDY_getMMIOReq(getMMIOReq_rdy),

      .putMMIOResp_data(putMMIOResp_data),
      .EN_putMMIOResp(putMMIOResp_en),
      .RDY_putMMIOResp(putMMIOResp_rdy));


   serialize_req srm
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .getMReq_en(getMReq_en),
      .getMReq_rdy(getMReq_rdy),
      .getMReq_data(getMReq_data),
      .req_axis_data(req_axis_data),
      .req_axis_tuser(req_axis_tuser),
      .req_axis_ready(req_axis_ready),
      .req_axis_valid(req_axis_valid));

   accumulate_resp arm
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .resp_axis_data(resp_axis_data),
      .resp_axis_valid(resp_axis_valid),
      .resp_axis_tuser(resp_axis_tuser),
      .resp_axis_ready(resp_axis_ready),
      .putMResp_data(putMResp_data),
      .putMResp_en(putMResp_en),
      .putMResp_rdy(putMResp_rdy));

endmodule

`default_nettype wire
