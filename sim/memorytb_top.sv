`timescale 1ns / 1ps
`default_nettype none

module memorytb_top
  (
   input wire 		ui_clk,
   input wire 		rst_in,

   output logic [7:0] 	uart_tx_data,
   input wire 		uart_tx_ready,
   output logic 	uart_tx_valid,

   output logic 	processor_done,

   // MIG UI --> generic outputs
   output logic [26:0] 	app_addr,
   output logic [2:0] 	app_cmd,
   output logic 	app_en,
   // MIG UI --> write outputs
   output logic [127:0] app_wdf_data,
   output logic 	app_wdf_end,
   output logic 	app_wdf_wren,
   output logic [15:0] 	app_wdf_mask,
   // MIG UI --> read inputs
   input wire [127:0] 	app_rd_data,
   input wire 		app_rd_data_end,
   input wire 		app_rd_data_valid,
   // MIG UI --> generic inputs
   input wire 		app_rdy,
   input wire 		app_wdf_rdy,
   // MIG UI --> misc
   output logic 	app_sr_req, 
   output logic 	app_ref_req,
   output logic 	app_zq_req, 
   input wire 		app_sr_active,
   input wire 		app_ref_ack,
   input wire 		app_zq_ack,
   input wire 		init_calib_complete
   );

   logic [127:0]       req_axis_data;
   logic 	       req_axis_tuser;
   logic 	       req_axis_ready;
   logic 	       req_axis_valid;

   logic [127:0]       resp_axis_data;
   logic 	       resp_axis_tuser;
   logic 	       resp_axis_ready;
   logic 	       resp_axis_valid;
   logic 	       resp_axis_af;
   
   logic [31:0]        debug_pc;
   
   wrapped_processor processor
     (.clk_in(ui_clk),
      .rst_in(rst_in), // processor is held at reset for longer than other components, so we can load memory in

      .req_axis_data(req_axis_data),
      .req_axis_tuser(req_axis_tuser),
      .req_axis_ready(req_axis_ready),
      .req_axis_valid(req_axis_valid),

      .resp_axis_data(resp_axis_data),
      .resp_axis_valid(resp_axis_valid),
      .resp_axis_tuser(resp_axis_tuser),
      .resp_axis_ready(resp_axis_ready),

      .uart_tx_data(uart_tx_data),
      .uart_tx_ready(uart_tx_ready),
      .uart_tx_valid(uart_tx_valid),

      .debug_pc(debug_pc),

      .processor_done(processor_done));

   logic 	       write_axis_ready[1:0];
   logic 	       write_axis_valid[1:0];
   logic [127:0]       write_axis_data[1:0];
   logic 	       write_axis_tuser[1:0];

   logic 	       read_axis_ready[1:0];
   logic 	       read_axis_valid[1:0];
   logic [127:0]       read_axis_data[1:0];
   logic 	       read_axis_tuser[1:0];
   logic 	       read_axis_af[1:0];

   logic [31:0]        debug_lane;

   // CHANNEL 0: processor core requests+responses
   assign req_axis_ready = write_axis_ready[0];
   assign write_axis_valid[0] = req_axis_valid;
   assign write_axis_data[0] = req_axis_data;
   assign write_axis_tuser[0] = req_axis_tuser;

   assign read_axis_ready[0] = resp_axis_ready;
   assign resp_axis_valid = read_axis_valid[0];
   assign resp_axis_data = read_axis_data[0];
   assign read_axis_af[0] = 1'b0;
   assign resp_axis_tuser = read_axis_tuser[0];

   // CHANNEL 1: not in use
   assign write_axis_valid[1] = 1'b0;
   assign read_axis_ready[1] = 1'b0;
   
   generate
      genvar 	       idx;
      for(idx = 0; idx < 2; idx++) begin: vcd_access
	 logic 	       write_axis_ready_vcd;
	 assign write_axis_ready_vcd = write_axis_ready[idx];
	 logic 	       write_axis_valid_vcd;
	 assign write_axis_valid_vcd = write_axis_valid[idx];
	 logic [127:0] write_axis_data_vcd;
	 assign write_axis_data_vcd = write_axis_data[idx];
	 logic 	       write_axis_tuser_vcd;
	 assign write_axis_tuser_vcd = write_axis_tuser[idx];
      
	 logic 	       read_axis_ready_vcd;
	 assign read_axis_ready_vcd = read_axis_ready[idx];
	 logic 	       read_axis_valid_vcd;
	 assign read_axis_valid_vcd = read_axis_valid[idx];
	 logic [127:0] read_axis_data_vcd;
	 assign read_axis_data_vcd = read_axis_data[idx];
	 logic 	       read_axis_tuser_vcd;
	 assign read_axis_tuser_vcd = read_axis_tuser[idx];
	 logic 	       read_axis_af_vcd;
	 assign read_axis_af_vcd = read_axis_af[idx];
      end
   endgenerate

   traffic_merger #(.CHANNEL_COUNT(2)) tg
     (.clk_in(ui_clk),
      .rst_in(rst_in),
      .debug_lane(debug_lane),
      
      .app_addr(app_addr),
      .app_cmd(app_cmd),
      .app_en(app_en),
      .app_wdf_data(app_wdf_data),
      .app_wdf_end(app_wdf_end),
      .app_wdf_wren(app_wdf_wren),
      .app_wdf_mask(app_wdf_mask),
      .app_rd_data(app_rd_data),
      .app_rd_data_valid(app_rd_data_valid),
      .app_rdy(app_rdy),
      .app_wdf_rdy(app_wdf_rdy),
      .app_sr_req(app_sr_req),
      .app_ref_req(app_ref_req),
      .app_zq_req(app_zq_req),
      .app_sr_active(app_sr_active),
      .app_ref_ack(app_ref_ack),
      .app_zq_ack(app_zq_ack),
      .init_calib_complete(init_calib_complete),

      .write_axis_data(write_axis_data),
      .write_axis_tuser(write_axis_tuser),
      .write_axis_valid(write_axis_valid),
      .write_axis_smallpile(),
      .write_axis_ready(write_axis_ready),

      .read_axis_data(read_axis_data),
      .read_axis_tuser(read_axis_tuser),
      .read_axis_valid(read_axis_valid),
      .read_axis_af(read_axis_af),
      .read_axis_ready(read_axis_ready));

endmodule

