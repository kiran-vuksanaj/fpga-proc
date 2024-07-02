`timescale 1ns / 1ps
`default_nettype none

// typedef struct packed {
//    logic [26:0] addr;
//    logic [26:0] stream_length;
//    logic 	wen;
// } channel_update;


module traffic_merger #
  (parameter CHANNEL_COUNT = 3,
   parameter MAX_CMD_QUEUE = 8)
  (
   output logic [31:0] 	debug_lane,
   input wire 		clk_in,
   input wire 		rst_in,

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
   output logic 	app_sr_req, // ??
   output logic 	app_ref_req,// ??
   output logic 	app_zq_req, // ??
   input wire 		app_sr_active,
   input wire 		app_ref_ack,
   input wire 		app_zq_ack,
   input wire 		init_calib_complete,

   // Write AXISes FIFO input
   input wire [127:0] 	write_axis_data [CHANNEL_COUNT-1:0],
   input wire 		write_axis_tuser [CHANNEL_COUNT-1:0],
   input wire 		write_axis_valid [CHANNEL_COUNT-1:0],
   input wire 		write_axis_smallpile [CHANNEL_COUNT-1:0],
   output logic 	write_axis_ready [CHANNEL_COUNT-1:0],

   // Read AXISes FIFO output
   // Read AXIS FIFO output
   output logic [127:0] read_axis_data [CHANNEL_COUNT-1:0],
   output logic 	read_axis_tuser [CHANNEL_COUNT-1:0],
   output logic 	read_axis_valid [CHANNEL_COUNT-1:0],
   input wire 		read_axis_af [CHANNEL_COUNT-1:0],
   input wire 		read_axis_ready [CHANNEL_COUNT-1:0]
   );

   localparam CHANNEL_INDEX = $clog2(CHANNEL_COUNT);

   localparam CMD_WRITE = 3'b000;
   localparam CMD_READ = 3'b001;
   
   logic [CHANNEL_INDEX-1:0] current_channel;
   logic [CHANNEL_INDEX-1:0] next_response_channel;

   // overall system control
   logic 		     hold_for_calib;

   // channel states
   logic 		     wen[CHANNEL_COUNT-1:0];
   logic [26:0] 	     cmd_addr[CHANNEL_COUNT-1:0];
   logic [26:0] 	     resp_addr[CHANNEL_COUNT-1:0];
   logic [26:0] 	     target_addr[CHANNEL_COUNT-1:0];
   logic [26:0] 	     command_addr[CHANNEL_COUNT-1:0];
   // channel combinational values
   logic 		     channel_ready[CHANNEL_COUNT-1:0];
   logic 		     read_cmd_done[CHANNEL_COUNT-1:0];
   logic 		     read_resp_done[CHANNEL_COUNT-1:0];
   logic [26:0]		     addr_diff[CHANNEL_COUNT-1:0]; // should never be higher than MAX_CMD_QUEUE
   logic 		     yield[CHANNEL_COUNT-1:0];
   logic 		     new_command_received[CHANNEL_COUNT-1:0];

   // for purposes of reading out values to vcd;
   generate
      genvar 		     idx;
      for (idx = 0; idx < CHANNEL_COUNT; idx++) begin: vcd_access
	 logic [127:0] 	write_axis_data_vcd;
	 assign write_axis_data_vcd = write_axis_data[idx];
	 logic 		write_axis_tuser_vcd;
	 assign write_axis_tuser_vcd = write_axis_tuser[idx];
	 logic 		write_axis_valid_vcd;
	 assign write_axis_valid_vcd = write_axis_valid[idx];
	 logic 		write_axis_smallpile_vcd;
	 assign write_axis_smallpile_vcd = write_axis_smallpile[idx];
	 logic 		write_axis_ready_vcd;
	 assign write_axis_ready_vcd = write_axis_ready[idx];
	 logic [127:0] 	read_axis_data_vcd;
	 assign read_axis_data_vcd = read_axis_data[idx];
	 logic 		read_axis_tuser_vcd;
	 assign read_axis_tuser_vcd = read_axis_tuser[idx];
	 logic 		read_axis_valid_vcd;
	 assign read_axis_valid_vcd = read_axis_valid[idx];
	 logic 		read_axis_af_vcd;
	 assign read_axis_af_vcd = read_axis_af[idx];
	 logic 		read_axis_ready_vcd;
	 assign read_axis_ready_vcd = read_axis_ready[idx];
	 logic 		wen_vcd;
	 assign wen_vcd = wen[idx];
	 logic [26:0] 	cmd_addr_vcd;
	 assign cmd_addr_vcd = cmd_addr[idx];
	 logic [26:0] 	resp_addr_vcd;
	 assign resp_addr_vcd = resp_addr[idx];
	 logic [26:0] 	target_addr_vcd;
	 assign target_addr_vcd = target_addr[idx];
	 logic [26:0] 	command_addr_vcd;
	 assign command_addr_vcd = command_addr[idx];
	 logic 		channel_ready_vcd;
	 assign channel_ready_vcd = channel_ready[idx];
	 logic 		read_cmd_done_vcd;
	 assign read_cmd_done_vcd = read_cmd_done[idx];
	 logic 		read_resp_done_vcd;
	 assign read_resp_done_vcd = read_resp_done[idx];
	 logic [26:0] 	addr_diff_vcd;
	 assign addr_diff_vcd = addr_diff[idx]; // should never be higher than MAX_CMD_QUEUE
	 logic 		yield_vcd;
	 assign yield_vcd = yield[idx];
	 logic 		new_command_received_vcd;
	 assign new_command_received_vcd = new_command_received[idx];
      end
   endgenerate

   always_comb begin
      for (int i = 0; i < CHANNEL_COUNT; i++) begin
	 read_cmd_done[i] = (cmd_addr[i] == target_addr[i]);
	 read_resp_done[i] = (resp_addr[i] == target_addr[i]);
	 addr_diff[i] = cmd_addr[i] - resp_addr[i];
	 
	 if (wen[i] == 1'b0) begin
	    channel_ready[i] = read_cmd_done[i] && read_resp_done[i] && app_rdy;
	    yield[i] = addr_diff[i] >= MAX_CMD_QUEUE || read_axis_af[i] || cmd_addr[i] == target_addr[i];
	 end else begin
	    channel_ready[i] = app_rdy && app_wdf_rdy;
	    yield[i] = ~write_axis_valid[i];
	 end
	 // write_axis_ready[i] = 1'b1;
	 write_axis_ready[i] = (channel_ready[i] && current_channel == i && ~hold_for_calib);
	 new_command_received[i] = write_axis_ready[i] && write_axis_valid[i] && write_axis_tuser[i];

	 // read responses
	 if (next_response_channel == i) begin
	    read_axis_data[i] = app_rd_data;
	    read_axis_tuser[i] = resp_addr[i] == command_addr[i];
	    read_axis_valid[i] = app_rd_data_valid;
	 end else begin
	    read_axis_data[i] = 0;
	    read_axis_tuser[i] = 1'b0;
	    read_axis_valid[i] = 1'b0;
	 end
      end // for (int i = 0; i < CHANNEL_COUNT; i++)
   end // always_comb

   channel_update command;
   assign command = write_axis_data[current_channel];

   logic write_command_success;
   logic read_command_success;
   logic command_success;

   assign write_command_success = wen[current_channel] &&
				  write_axis_ready[current_channel] &&
				  write_axis_valid[current_channel] &&
				  ~write_axis_tuser[current_channel];
   assign read_command_success = ~wen[current_channel] &&
				 ~yield[current_channel] &&
				 app_rdy;
   assign command_success = write_command_success || read_command_success;
   logic [CHANNEL_COUNT-1:0] yields = {yield[0], yield[1], yield[2]};
   
   generate
      genvar i;
      for(i = 0; i < CHANNEL_COUNT; i++) begin: cursors

	 cursor #(.WIDTH(27)) cmd_addr_cur
	      (.clk_in(clk_in),
	       .rst_in(rst_in),
	       .incr_in( command_success && current_channel == i ),
	       .setval_in(new_command_received[i]),
	       .manual_in(command.addr),
	       .cursor_out(cmd_addr[i]));

	 cursor #(.WIDTH(27)) resp_addr_cur
	   (.clk_in(clk_in),
	    .rst_in(rst_in),
	    .incr_in( app_rd_data_valid && next_response_channel == i ),
	    .setval_in(new_command_received[i]),
	    .manual_in(command.addr),
	    .cursor_out(resp_addr[i]));

	 always_ff @(posedge clk_in) begin
	    if (rst_in) begin
	       target_addr[i] <= 0;
	       command_addr[i] <= 0;
	       wen[i] <= 0;
	    end else if (new_command_received[i]) begin 
	       target_addr[i] <= command.addr + command.stream_length;
	       command_addr[i] <= command.addr;
	       wen[i] <= command.wen;
	    end
	 end
	    
	 
      end
   endgenerate

   cursor #
     (.WIDTH(CHANNEL_INDEX), .ROLLOVER(CHANNEL_COUNT))
   current_channel_cursor
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .incr_in( yield[current_channel] && ~hold_for_calib),
      .cursor_out( current_channel ));
   
   read_resp_queue #(.INDEX_WIDTH(CHANNEL_INDEX), .QUEUE_LENGTH(CHANNEL_COUNT*MAX_CMD_QUEUE+1)) rqm
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .current_channel(current_channel),
      .read_cmd_success( read_command_success ),
      .next_channel(next_response_channel),
      .read_data_ready(app_rd_data_valid));
   
   always_comb begin
      if (wen[current_channel] && write_axis_ready[current_channel] && write_axis_valid[current_channel] && ~write_axis_tuser[current_channel]) begin
	 // issue write command
	 app_addr = cmd_addr[current_channel] << 7;
	 app_cmd = CMD_WRITE;
	 app_en = 1'b1;
	 app_wdf_wren = 1'b1;
	 app_wdf_data = write_axis_data[current_channel];
	 app_wdf_end = 1'b1;
      end else if (~wen[current_channel] && ~yield[current_channel] && app_rdy) begin
	 // issue read command
	 app_addr = cmd_addr[current_channel] << 7;
	 app_cmd = CMD_READ;
	 app_en = 1'b1;
	 app_wdf_wren = 1'b0;
	 app_wdf_data = 0;
	 app_wdf_end = 1'b0;
      end else begin
	 app_addr = 0;
	 app_cmd = 0;
	 app_en = 1'b0;
	 app_wdf_wren = 1'b0;
	 app_wdf_data = 0;
	 app_wdf_end = 1'b0;
      end
   end // always_comb

   
   // unused signals
   assign app_sr_req = 0;
   assign app_ref_req = 0;
   assign app_zq_req = 0;
   assign app_wdf_mask = 16'b0;

   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 hold_for_calib <= 1'b1;
      end else if (hold_for_calib) begin
	 hold_for_calib <= ~init_calib_complete;
      end else begin
	 hold_for_calib <= hold_for_calib;
      end
   end

   assign debug_lane = cmd_addr[0];

endmodule

module read_resp_queue #
  (parameter INDEX_WIDTH = 1,
   parameter QUEUE_LENGTH = 1)
   (input wire clk_in,
    input wire 			   rst_in,
    input wire [INDEX_WIDTH-1:0]   current_channel,
    input wire 			   read_cmd_success,
    output logic [INDEX_WIDTH-1:0] next_channel,
    input wire 			   read_data_ready);

   localparam QUEUE_INDEX = $clog2(QUEUE_LENGTH);
   
   logic [INDEX_WIDTH-1:0] 	   queue [QUEUE_LENGTH-1:0];
   logic [QUEUE_INDEX-1:0] 	   new_cmd_index;
   logic [QUEUE_INDEX-1:0] 	   next_rsp_index;

   cursor #(.WIDTH(QUEUE_INDEX),.ROLLOVER(QUEUE_LENGTH)) nci_cur
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .incr_in(read_cmd_success),
      .setval_in(0),
      .manual_in(),
      .cursor_out(new_cmd_index));

   cursor #(.WIDTH(QUEUE_INDEX),.ROLLOVER(QUEUE_LENGTH)) nri_cur
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .incr_in(read_data_ready),
      .setval_in(0),
      .manual_in(),
      .cursor_out(next_rsp_index));

   assign next_channel = queue[next_rsp_index];
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 for(int i = 0; i < QUEUE_LENGTH; i++) begin
	    queue[i] <= 0;
	 end
      end else begin
	 if( read_cmd_success ) queue[new_cmd_index] <= current_channel;
      end
   end

endmodule

`default_nettype wire
