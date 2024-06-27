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

module top_level
  (
   input wire 	       clk_100mhz,
   input wire 	       uart_rxd,
   input wire [3:0]    btn,
   input wire [15:0]   sw,
   output logic        uart_txd,
   output logic [2:0]  rgb0,
   output logic [2:0]  rgb1,
   output logic [3:0]  ss0_an,
   output logic [3:0]  ss1_an,
   output logic [6:0]  ss0_c,
   output logic [6:0]  ss1_c,
   output logic [15:0] led,
   // DDR3 ports
   inout wire [15:0]   ddr3_dq,
   inout wire [1:0]    ddr3_dqs_n,
   inout wire [1:0]    ddr3_dqs_p,
   output wire [12:0]  ddr3_addr,
   output wire [2:0]   ddr3_ba,
   output wire 	       ddr3_ras_n,
   output wire 	       ddr3_cas_n,
   output wire 	       ddr3_we_n,
   output wire 	       ddr3_reset_n,
   output wire 	       ddr3_ck_p,
   output wire 	       ddr3_ck_n,
   output wire 	       ddr3_cke,
   output wire [1:0]   ddr3_dm,
   output wire 	       ddr3_odt
   );
   localparam BAUD = 57600;
   
   
   logic 	       sys_clk;
   logic 	       clk_migref;

   logic 	       sys_rst;
   assign sys_rst = btn[0];

   clk_wiz_mig_clk_wiz clocking_wizard
     (.clk_in1(clk_100mhz),
      .clk_default(sys_clk),
      .clk_mig(clk_migref), // 200MHz
      .reset(0));

   logic 	       ui_clk;
   logic 	       sys_rst_ui;

   // bonus signal to prevent processor from running away while there's no assembly
   logic 	       proc_release;
   always_ff @(posedge sys_clk) begin
      if (sys_rst) begin
	 proc_release <= 1'b0;
      end else begin
	 if (btn[2]) begin
	    proc_release <= 1'b1;
	 end
      end
   end


   // CHAPTER: UART receiving assembly
   logic 	       uart_rxd_buf0;
   logic 	       uart_rxd_buf1;

   logic 	       uart_valid;
   logic [7:0] 	       data_uart;
   
   always_ff @(posedge sys_clk) begin
      uart_rxd_buf0 <= uart_rxd;
      uart_rxd_buf1 <= uart_rxd_buf0;
   end

   
   uart_rcv
     #(.BAUD_RATE(BAUD),
       .CLOCK_SPEED(100_000_000))
   urm
     (.clk_in(sys_clk),
      .rst_in(sys_rst),
      .uart_rx(uart_rxd_buf1),
      .valid_out(uart_valid),
      .data_out(data_uart));

   logic [127:0]       assembly_axis_data;
   logic 	       assembly_axis_ready;
   logic 	       assembly_axis_valid;
   logic 	       assembly_axis_tuser;

   channel_update initialize_assembly;
   assign initialize_assembly = { 27'b0, 27'b0, 1'b1 };

   parse_asm pam
     (.clk_in(sys_clk),
      .rst_in(sys_rst),
      .valid_fbyte(uart_valid),
      .fbyte(data_uart),
      .axis_tuser(assembly_axis_tuser),
      .axis_data(assembly_axis_data),
      .axis_ready(assembly_axis_ready),
      .axis_valid(assembly_axis_valid));

   logic [127:0]       ui_assembly_axis_data;
   logic 	       ui_assembly_axis_ready;
   logic 	       ui_assembly_axis_valid;
   logic 	       ui_assembly_axis_tuser;
   
   ddr_fifo assembly_fifo
     (.sender_rst(sys_rst),
      .sender_clk(sys_clk),
      .sender_axis_tvalid(assembly_axis_valid),
      .sender_axis_tready(assembly_axis_ready),
      .sender_axis_tdata(assembly_axis_data),
      .sender_axis_tuser(assembly_axis_tuser),
      .receiver_clk(ui_clk),
      .receiver_axis_tvalid(ui_assembly_axis_valid),
      .receiver_axis_tready(ui_assembly_axis_ready),
      .receiver_axis_tdata(ui_assembly_axis_data),
      .receiver_axis_tuser(ui_assembly_axis_tuser));
   

   logic 	       getMReq_en;
   logic 	       getMReq_rdy;
   logic [538:0]       getMReq_data;

   logic 	       getMMIOReq_en;
   logic 	       getMMIOReq_rdy;
   logic [67:0]        getMMIOReq_data;

   logic 	       putMResp_en;
   logic 	       putMResp_rdy;
   logic [511:0]       putMResp_data;
   
   logic 	       putMMIOResp_en;
   logic 	       putMMIOResp_rdy;
   logic [67:0]	       putMMIOResp_data;

   logic [7:0] 	       uart_tx_data;
   logic 	       uart_tx_ready;
   logic 	       uart_tx_valid;
   logic 	       processor_done;
      
   handle_mmio hmm
     (.clk_in(sys_clk),
      .rst_in(sys_rst),
      
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
   
   uart_transmitter
     #(.BAUD_RATE(BAUD),
       .CLOCK_SPEED(100_000_000)) utm
       (.clk_in(sys_clk),
	.rst_in(sys_rst),
	.data_in(uart_tx_data),
	.valid_in(uart_tx_valid),
	.ready_in(uart_tx_ready),
	.uart_tx(uart_txd));
   
   logic 	       proc_reset;
   assign proc_reset = (sys_rst || ~proc_release);

   logic [31:0]        debug_pc;
   logic 	       debug_epoch;
   
   mkProcCore processor
     (.CLK(sys_clk),
      .RST_N(~proc_reset), // reset active low, i think by default
      .debug_pc(debug_pc),
      .debug_epoch(debug_epoch),

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

   logic [127:0]       req_axis_data;
   logic 	       req_axis_tuser;
   logic 	       req_axis_ready;
   logic 	       req_axis_valid;

   logic [127:0]       ui_req_axis_data;
   logic 	       ui_req_axis_tuser;
   logic 	       ui_req_axis_ready;
   logic 	       ui_req_axis_valid;

   logic [127:0]       resp_axis_data;
   logic 	       resp_axis_tuser;
   logic 	       resp_axis_ready;
   logic 	       resp_axis_valid;
   logic 	       resp_axis_af;
   
   logic [127:0]       ui_resp_axis_data;
   logic 	       ui_resp_axis_tuser;
   logic 	       ui_resp_axis_ready;
   logic 	       ui_resp_axis_valid;


   // pathway: processor request -> serialize -> clock domain cross -> channel merger
   logic [1:0] 	       srstate;
   
   serialize_req srm
     (.clk_in(sys_clk),
      .rst_in(sys_rst),
      .getMReq_en(getMReq_en),
      .getMReq_rdy(getMReq_rdy),
      .getMReq_data(getMReq_data),
      .req_axis_data(req_axis_data),
      .req_axis_tuser(req_axis_tuser),
      .req_axis_ready(req_axis_ready),
      .req_axis_valid(req_axis_valid),
      .srstate(srstate));

   ddr_fifo proc_req
     (.sender_rst(sys_rst),
      .sender_clk(sys_clk),
      .sender_axis_tready(req_axis_ready),
      .sender_axis_tvalid(req_axis_valid),
      .sender_axis_tdata(req_axis_data),
      .sender_axis_tuser(req_axis_tuser),
      .receiver_clk(ui_clk),
      .receiver_axis_tvalid(ui_req_axis_valid),
      .receiver_axis_tready(ui_req_axis_ready),
      .receiver_axis_tdata(ui_req_axis_data),
      .receiver_axis_tuser(ui_req_axis_tuser));

   // pathway: channel merger -> clock domain cross -> accumulator -> processor response
   ddr_fifo proc_resp
     (.sender_rst(sys_rst_ui),
      .sender_clk(ui_clk),
      .sender_axis_tvalid(ui_resp_axis_valid),
      .sender_axis_tready(ui_resp_axis_ready),
      .sender_axis_tdata(ui_resp_axis_data),
      .sender_axis_tuser(ui_resp_axis_tuser),
      .sender_axis_prog_full(resp_axis_af),
      .receiver_clk(sys_clk),
      .receiver_axis_tvalid(resp_axis_valid),
      .receiver_axis_tready(resp_axis_ready),
      .receiver_axis_tdata(resp_axis_data),
      .receiver_axis_tuser(resp_axis_tuser));

   accumulate_resp arm
     (.clk_in(sys_clk),
      .rst_in(sys_rst),
      .resp_axis_data(resp_axis_data),
      .resp_axis_valid(resp_axis_valid),
      .resp_axis_tuser(resp_axis_tuser),
      .resp_axis_ready(resp_axis_ready),
      .putMResp_data(putMResp_data),
      .putMResp_en(putMResp_en),
      .putMResp_rdy(putMResp_rdy));
   
   logic [127:0]       ssc_req_axis_data;
   logic 	       ssc_req_axis_tuser;
   logic 	       ssc_req_axis_ready;
   logic 	       ssc_req_axis_valid;

   channel_update sw_cmd;
   assign sw_cmd.addr = sw[15:2];
   assign sw_cmd.stream_length = 27'b1;
   assign sw_cmd.wen = 1'b0;

   assign ssc_req_axis_data = sw_cmd;
   assign ssc_req_axis_valid = 1'b1;
   assign ssc_req_axis_tuser = 1'b1;

   logic [127:0]       ui_ssc_req_axis_data;
   logic 	       ui_ssc_req_axis_tuser;
   logic 	       ui_ssc_req_axis_ready;
   logic 	       ui_ssc_req_axis_valid;

   ddr_fifo req_fifo
     (.sender_rst(sys_rst),
      .sender_clk(sys_clk),
      .sender_axis_tvalid(ssc_req_axis_valid),
      .sender_axis_tready(ssc_req_axis_ready),
      .sender_axis_tdata(ssc_req_axis_data),
      .sender_axis_tuser(ssc_req_axis_tuser),
      .receiver_clk(ui_clk),
      .receiver_axis_tvalid(ui_ssc_req_axis_valid),
      .receiver_axis_tready(ui_ssc_req_axis_ready),
      .receiver_axis_tdata(ui_ssc_req_axis_data),
      .receiver_axis_tuser(ui_ssc_req_axis_tuser));

   logic [127:0]       ui_ssc_resp_axis_data;
   logic 	       ui_ssc_resp_axis_tuser;
   logic 	       ui_ssc_resp_axis_ready;
   logic 	       ui_ssc_resp_axis_valid;

   
   logic [127:0]       ssc_resp_axis_data;
   logic 	       ssc_resp_axis_tuser;
   logic 	       ssc_resp_axis_ready;
   logic 	       ssc_resp_axis_valid;

   logic 	       ssc_resp_axis_af;
   
   ddr_fifo resp_fifo
     (.sender_rst(sys_rst_ui),
      .sender_clk(ui_clk),
      .sender_axis_tvalid(ui_ssc_resp_axis_valid),
      .sender_axis_tready(ui_ssc_resp_axis_ready),
      .sender_axis_tdata(ui_ssc_resp_axis_data),
      .sender_axis_tuser(ui_ssc_resp_axis_tuser),
      .sender_axis_prog_full(ssc_resp_axis_af),
      .receiver_clk(sys_clk),
      .receiver_axis_tvalid(ssc_resp_axis_valid),
      .receiver_axis_tready(ssc_resp_axis_ready),
      .receiver_axis_tdata(ssc_resp_axis_data),
      .receiver_axis_tuser(ssc_resp_axis_tuser));

   assign ssc_resp_axis_ready = 1'b1;
   logic [127:0]       response_hold;
   logic [31:0]        response_hold_chunks[3:0];
   assign response_hold_chunks[0] = response_hold[31:0];
   assign response_hold_chunks[1] = response_hold[63:32];
   assign response_hold_chunks[2] = response_hold[95:64];
   assign response_hold_chunks[3] = response_hold[127:96];

   logic [31:0]        mmio_addr_hold;
   logic [31:0]        mmio_data_hold;
   
   logic [31:0]        debug_lane;
   
   always_ff @(posedge sys_clk) begin
      if (sys_rst) begin
	 response_hold <= 128'b0;
	 mmio_addr_hold <= 32'habababab;
	 mmio_data_hold <= 32'hbcbcbcbc;
      end
      if (ssc_resp_axis_valid && ssc_resp_axis_ready) begin
	 response_hold <= ssc_resp_axis_data;
      end
      if (getMMIOReq_en) begin
	 mmio_addr_hold <= getMMIOReq_data[63:32];
	 mmio_data_hold <= getMMIOReq_data[31:0];
      end
   end

   logic [1:0] offset;
   assign offset = sw[1:0];
   
   logic [31:0] val_to_display;
   // assign val_to_display = response_hold_chunks[offset];
   assign val_to_display = btn[1] ? (btn[3] ? mmio_addr_hold : debug_pc) : (btn[3] ? mmio_data_hold : response_hold_chunks[offset]);
   

   logic [6:0] 	       ss_c;
   assign ss0_c = ss_c;
   assign ss1_c = ss_c;
   seven_segment_controller ssc
     (.clk_in(sys_clk),
      .rst_in(sys_rst),
      .val_in(val_to_display),
      .en_in(1'b1),
      .cat_out(ss_c),
      .an_out({ss0_an,ss1_an}));
   

   // channel merger (UI clock domain) connections

   logic 	       tm_write_axis_ready[2:0];
   logic 	       tm_write_axis_valid[2:0];
   logic [127:0]       tm_write_axis_data[2:0];
   logic 	       tm_write_axis_tuser[2:0];

   logic 	       tm_read_axis_ready[2:0];
   logic 	       tm_read_axis_valid[2:0];
   logic [127:0]       tm_read_axis_data[2:0];
   logic 	       tm_read_axis_tuser[2:0];
   logic 	       tm_read_axis_af[2:0];

   // CHANNEL 0: processor core requests+responses
   assign ui_req_axis_ready = tm_write_axis_ready[0];
   assign tm_write_axis_valid[0] = ui_req_axis_valid;
   assign tm_write_axis_data[0] = ui_req_axis_data;
   assign tm_write_axis_tuser[0] = ui_req_axis_tuser;

   assign tm_read_axis_ready[0] = ui_resp_axis_ready;
   assign ui_resp_axis_valid = tm_read_axis_valid[0];
   assign ui_resp_axis_data = tm_read_axis_data[0];
   assign ui_resp_axis_tuser = tm_read_axis_tuser[0];

   // CHANNEL 1: uart write our machine code

   assign ui_assembly_axis_ready = tm_write_axis_ready[1];
   assign tm_write_axis_valid[1] = ui_assembly_axis_valid;
   assign tm_write_axis_data[1] = ui_assembly_axis_data;
   assign tm_write_axis_tuser[1] = ui_assembly_axis_tuser;
   // no reads
   assign tm_read_axis_ready[1] = 1'b0;

   // CHANNEL 2: display memory contents on seven segment

   assign ui_ssc_req_axis_ready = tm_write_axis_ready[2];
   assign tm_write_axis_valid[2] = ui_ssc_req_axis_valid;
   assign tm_write_axis_data[2] = ui_ssc_req_axis_data;
   assign tm_write_axis_tuser[2] = ui_ssc_req_axis_tuser;

   assign tm_read_axis_ready[2] = ui_ssc_resp_axis_ready;
   assign ui_ssc_resp_axis_valid = tm_read_axis_valid[2];
   assign ui_ssc_resp_axis_data = tm_read_axis_data[2];
   assign ui_ssc_resp_axis_tuser = tm_read_axis_tuser[2];
   
   
   // CHANNEL MERGER AND MIG
   // mig module
   // user interface signals
   logic [26:0]        app_addr;
   logic [2:0] 	       app_cmd;
   logic 	       app_en;
   logic [127:0]       app_wdf_data;
   logic 	       app_wdf_end;
   logic 	       app_wdf_wren;
   logic [127:0]       app_rd_data;
   logic 	       app_rd_data_end;
   logic 	       app_rd_data_valid;
   logic 	       app_rdy;
   logic 	       app_wdf_rdy;
   logic 	       app_sr_req;
   logic 	       app_ref_req;
   logic 	       app_zq_req;
   logic 	       app_sr_active;
   logic 	       app_ref_ack;
   logic 	       app_zq_ack;
   // logic 	       ui_clk; // ** CLOCK FOR MIG INTERACTIONS!! ** defined further up
   logic 	       ui_clk_sync_rst;
   logic [15:0]        app_wdf_mask;
   logic 	       init_calib_complete;
   logic [11:0]        device_temp;

   assign sys_rst_ui = ui_clk_sync_rst;

   traffic_merger #(.CHANNEL_COUNT(3)) tg
     (.clk_in(ui_clk),
      .rst_in(sys_rst_ui),
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

      .write_axis_data(tm_write_axis_data),
      .write_axis_tuser(tm_write_axis_tuser),
      .write_axis_valid(tm_write_axis_valid),
      .write_axis_smallpile(),
      .write_axis_ready(tm_write_axis_ready),

      .read_axis_data(tm_read_axis_data),
      .read_axis_tuser(tm_read_axis_tuser),
      .read_axis_valid(tm_read_axis_valid),
      .read_axis_af(tm_read_axis_af),
      .read_axis_ready(tm_read_axis_ready));

   
   ddr3_mig ddr3_mig_inst 
     (
      .ddr3_dq(ddr3_dq),
      .ddr3_dqs_n(ddr3_dqs_n),
      .ddr3_dqs_p(ddr3_dqs_p),
      .ddr3_addr(ddr3_addr),
      .ddr3_ba(ddr3_ba),
      .ddr3_ras_n(ddr3_ras_n),
      .ddr3_cas_n(ddr3_cas_n),
      .ddr3_we_n(ddr3_we_n),
      .ddr3_reset_n(ddr3_reset_n),
      .ddr3_ck_p(ddr3_ck_p),
      .ddr3_ck_n(ddr3_ck_n),
      .ddr3_cke(ddr3_cke),
      .ddr3_dm(ddr3_dm),
      .ddr3_odt(ddr3_odt),
      .sys_clk_i(clk_migref),
      .app_addr(app_addr),
      .app_cmd(app_cmd),
      .app_en(app_en),
      .app_wdf_data(app_wdf_data),
      .app_wdf_end(app_wdf_end),
      .app_wdf_wren(app_wdf_wren),
      .app_rd_data(app_rd_data),
      .app_rd_data_end(app_rd_data_end),
      .app_rd_data_valid(app_rd_data_valid),
      .app_rdy(app_rdy),
      .app_wdf_rdy(app_wdf_rdy), 
      .app_sr_req(app_sr_req),
      .app_ref_req(app_ref_req),
      .app_zq_req(app_zq_req),
      .app_sr_active(app_sr_active),
      .app_ref_ack(app_ref_ack),
      .app_zq_ack(app_zq_ack),
      .ui_clk(ui_clk), 
      .ui_clk_sync_rst(ui_clk_sync_rst),
      .app_wdf_mask(app_wdf_mask),
      .init_calib_complete(init_calib_complete),
      .device_temp(device_temp),
      .sys_rst(!sys_rst) // active low
      );
   

   logic [7:0] 	       uart_tx_count;
   always_ff @(posedge sys_clk) begin
      if(sys_rst) begin
	uart_tx_count <= 1'b0;
      end else begin
	 uart_tx_count <= uart_tx_count + (uart_tx_valid && uart_tx_ready);
      end
   end
   
   assign led[0] = getMMIOReq_rdy;
   assign led[1] = getMReq_rdy;
   assign led[2] = putMMIOResp_rdy;
   assign led[3] = putMResp_rdy;

   assign led[4] = init_calib_complete;
   // assign led[5] = assembly_axis_ready;
   // assign led[6] = assembly_axis_valid;
   // assign led[7] = req_axis_ready;
   // assign led[8] = req_axis_valid;
   // assign led[9] = resp_axis_ready;
   // assign led[10] = resp_axis_valid;
   // assign led[12:11] = srstate;
   
   assign led[5] = proc_reset;
   assign led[6] = debug_epoch;
   assign led[7] = processor_done;
   assign led[15:8] = uart_tx_count;

   
		   

endmodule
`default_nettype wire
