`timescale 1ns / 1ps
`default_nettype none

module serialize_request
  (
   input wire 		clk_in,
   input wire 		rst_in,
   input wire [538:0] 	request_data,
   input wire 		request_valid,
   output logic 	request_ready,
   output logic [127:0] axis_data,
   output logic 	axis_valid,
   output logic 	axis_tuser,
   output logic 	axis_ready);
   
endmodule // serialize_request

module accumulate_response
  (
   input wire 		clk_in,
   input wire 		rst_in,
   input wire [127:0] 	axis_data,
   input wire 		axis_valid,
   input wire 		axis_tuser,
   output logic 	axis_ready,
   output logic [511:0] response_data,
   output logic 	response_valid,
   input wire 		response_ready);

   

endmodule
`default_nettype wire
