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

`ifndef PARSED_META
`define PARSED_META
typedef struct packed {
   logic [2:0] channel;
   logic [26:0] addr;
   logic 	wen;
} parsed_meta;
`endif


module top_level
  (
   input wire 	       clk_100mhz,
   output logic [15:0] led,
   input wire [7:0]    pmoda,
   input wire [2:0]    pmodb,
   output logic        pmodb_clk,
   inout wire 	       pmodb_scl,
   inout wire 	       pmodb_sda,
   input wire [15:0]   sw,
   input wire [3:0]    btn,
   output logic [2:0]  rgb0,
   output logic [2:0]  rgb1,
   // seven segment
   output logic [3:0]  ss0_an,//anode control for upper four digits of seven-seg display
   output logic [3:0]  ss1_an,//anode control for lower four digits of seven-seg display
   output logic [6:0]  ss0_c, //cathode controls for the segments of upper four digits
   output logic [6:0]  ss1_c, //cathod controls for the segments of lower four digits
   // uart for manta
   input wire 	       uart_rxd,
   output logic        uart_txd,
   // hdmi port
   output logic [2:0]  hdmi_tx_p, //hdmi output signals (positives) (blue, green, red)
   output logic [2:0]  hdmi_tx_n, //hdmi output signals (negatives) (blue, green, red)
   output logic        hdmi_clk_p, hdmi_clk_n, //differential hdmi clock
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
   assign rgb0 = 0;
   assign rgb1 = 0;
   
   localparam BAUD = 57600;
   localparam CAMERA_FB_ADDR = 27'h1000;
   
   logic 	       clk_100_passthrough;
   logic 	       sys_clk;
   logic 	       clk_camera;
   logic 	       clk_pixel;
   logic 	       clk_5x;
   logic 	       clk_xc;

   logic 	       ui_clk;
   logic 	       sys_rst_ui;

   camera_clocks_clk_wiz
     (.clk_in1(clk_100mhz),
      .clk_camera(clk_camera),
      .clk_100a(clk_100_passthrough),
      .clk_100b(sys_clk),
      .clk_xc(clk_xc),
      .reset(0));

   assign pmodb_clk = clk_xc;

   hdmi_clocks_clk_wiz
     (.clk_in1(clk_100_passthrough),
      .clk_pixel(clk_pixel),
      .clk_5x(clk_5x),
      .reset(0));
   
   logic 	       sys_rst;
   assign sys_rst = btn[0];


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

   logic trigger_btn_camera;
   assign btn[1] = trigger_btn_camera;

   // CHAPTER: Camera Handler

   // camera_bare
   logic 	       hsync_raw;
   logic 	       hsync;
   logic 	       vsync_raw;
   logic 	       vsync;
   
   logic [15:0]        data;
   logic 	       valid_pixel;
   logic 	       valid_byte;
      
   // buffering
   logic [2:0] 	       pmodb_buf0;
   logic [7:0] 	       pmoda_buf0;
   
   logic [2:0] 	       pmodb_buf; // buffer, to make sure values only update on our clock domain!p
   logic [7:0] 	       pmoda_buf;
   
   // ==================== CHAPTER: CAMERA CAPTURE =======================
   always_ff @(posedge clk_camera) begin
      pmoda_buf0 <= pmoda;
      pmodb_buf0 <= pmodb;
      
      pmoda_buf <= pmoda_buf0;
      pmodb_buf <= pmodb_buf0;
   end

   camera_bare cbm
     (.clk_pixel_in(clk_camera),
      .pclk_cam_in(pmodb_buf[0] ),
      .hs_cam_in(pmodb_buf[2]),
      .vs_cam_in(pmodb_buf[1]),
      .rst_in(sys_rst),
      .data_cam_in(pmoda_buf),
      .hs_cam_out(hsync_raw),
      .vs_cam_out(vsync_raw),
      .data_out(data),
      .valid_out(valid_pixel),
      .valid_byte(valid_byte)
      );
   // assign hsync = sw[0] ^ hsync_raw; // if sw[0], invert hsync
   // assign vsync = sw[1] ^ vsync_raw; // if sw[1], invert vsync
   assign hsync = hsync_raw;
   assign vsync = vsync_raw;

   logic valid_cc;
   logic [15:0] pixel_cc;
   logic [12:0] hcount_cc;
   logic [11:0] vcount_cc;

   camera_coord ccm
     (.clk_in(clk_camera),
      .rst_in(sys_rst),
      .valid_in(valid_pixel),
      .data_in(data),
      .hsync_in(hsync),
      .vsync_in(vsync),
      .valid_out(valid_cc),
      .data_out(pixel_cc),
      .hcount_out(hcount_cc),
      .vcount_out(vcount_cc)
      );

   // pass pixels into the phrase builder
   // ignore the ready signal! if its not ready, data will just be missed.
   // nothing else can be done since this is just coming at the rate of the camera
   logic 	phrase_axis_valid;
   logic 	phrase_axis_ready;

   logic [127:0] cam_phrase_data;
   logic [127:0] phrase_axis_data;

   logic 	 newframe_cc;
   logic 	 phrase_axis_tuser;
   logic 	 ready_builder;
   
   assign newframe_cc = (hcount_cc <= 1 && vcount_cc == 0);

   logic 	 freeze_frame;
   always_ff @(posedge clk_camera) begin
      if(sys_rst)
	freeze_frame <= 0;
      else if (newframe_cc)
	freeze_frame <= sw[0];
   end
   
   build_wr_data
     (.clk_in(clk_camera),
      .rst_in(sys_rst),
      .valid_in(valid_cc && ~freeze_frame),
      .ready_in(ready_builder), // discarded currently
      // .data_in(pixel_cc_filter),// temporary test value
      .data_in(pixel_cc),
      .newframe_in(newframe_cc),
      .valid_out(phrase_axis_valid),
      .ready_out(phrase_axis_ready),
      .data_out(cam_phrase_data),
      .tuser_out(phrase_axis_tuser)
      );

   channel_update write_addr_cmd = {CAMERA_FB_ADDR, 27'((1280*720)>>3),1'b1};
   assign phrase_axis_data = phrase_axis_tuser ? write_addr_cmd : cam_phrase_data;

   // =============== CHAPTER: MEMORY MIG STUFF ====================

   logic 	 cam_write_axis_valid;
   logic 	 cam_write_axis_ready;
   logic [127:0] cam_write_axis_phrase;
   logic 	 cam_write_axis_tuser;

   logic 	 small_pile;

   ddr_fifo camera_write
     (.sender_rst(sys_rst), 
      .sender_clk(clk_camera),
      .sender_axis_tvalid(phrase_axis_valid),
      .sender_axis_tready(phrase_axis_ready),
      .sender_axis_tdata(phrase_axis_data),
      .sender_axis_tuser(phrase_axis_tuser),
      .receiver_clk(ui_clk),
      .receiver_axis_tvalid(cam_write_axis_valid),
      .receiver_axis_tready(cam_write_axis_ready), // ready will spit you data! use in proper state
      .receiver_axis_tdata(cam_write_axis_phrase),
      .receiver_axis_tuser(cam_write_axis_tuser));

   logic [127:0]       hdmi_resp_axis_data;
   logic 	       hdmi_resp_axis_tuser;
   logic 	       hdmi_resp_axis_ready;
   logic 	       hdmi_resp_axis_valid;

   logic 	       hdmi_resp_axis_af;

   logic 	       hdmi_axis_valid;
   logic 	       hdmi_axis_ready;
   logic [127:0]       hdmi_axis_data;
   logic 	       hdmi_axis_tuser;
   
   ddr_fifo hdmi_read
     (.sender_rst(sys_rst_ui), // active low
      .sender_clk(ui_clk),
      .sender_axis_tvalid(hdmi_resp_axis_valid),
      .sender_axis_tready(hdmi_resp_axis_ready),
      .sender_axis_tdata(hdmi_resp_axis_data),
      .sender_axis_tuser(hdmi_resp_axis_tuser),
      .sender_axis_prog_full(hdmi_resp_axis_af),
      .receiver_clk(clk_pixel),
      .receiver_axis_tvalid(hdmi_axis_valid),
      .receiver_axis_tready(hdmi_axis_ready), // ready will spit you data! use in proper state
      .receiver_axis_tdata(hdmi_axis_data),
      .receiver_axis_tuser(hdmi_axis_tuser));

   logic [15:0]  hdmi_pixel;
   logic 	 hdmi_pixel_ready;
   logic 	 hdmi_pixel_valid;
   logic 	 hdmi_pixel_nf;

   digest_phrase
     (.clk_in(clk_pixel),
      .rst_in(sys_rst),
      .valid_phrase(hdmi_axis_valid),
      .ready_phrase(hdmi_axis_ready),
      .phrase_data(hdmi_axis_data),
      .phrase_tuser(hdmi_axis_tuser),
      .valid_word(hdmi_pixel_valid),
      .ready_word(hdmi_pixel_ready),
      .newframe_out(hdmi_pixel_nf),
      .word(hdmi_pixel));
   // =============== CHAPTER: HDMI OUTPUT =========================
   
   logic [9:0] tmds_10b [0:2]; //output of each TMDS encoder!
   logic       tmds_signal [2:0]; //output of each TMDS serializer!
   
   // video signal generator
   logic 	       hsync_hdmi;
   logic 	       vsync_hdmi;
   logic [10:0]        hcount_hdmi;
   logic [9:0] 	       vcount_hdmi;
   logic 	       active_draw_hdmi;
   logic 	       new_frame_hdmi;
   logic [5:0] 	       frame_count_hdmi;

   // rgb output values
   logic [7:0] 	       red,green,blue;
   
   
   // // for now:
   // assign red = 8'hFF;
   // assign green = 8'h77;
   // assign blue = 8'hAA;

   // hold ready signal low until newframe_hdmi
   assign hdmi_pixel_ready = active_draw_hdmi && ( ~hdmi_pixel_nf || (vcount_hdmi == 0 && hcount_hdmi == 0));

   always_comb begin
      if (hdmi_pixel_ready) begin
	 if (sw[1]) begin
	    red = {hdmi_pixel[15:11],3'b0};
	    green = {hdmi_pixel[10:5],2'b0};
	    blue = {hdmi_pixel[4:0], 3'b0};
	 end else begin
	    red = hdmi_pixel[7:0];
	    green = hdmi_pixel[7:0];
	    blue = hdmi_pixel[7:0];
	 end
      end else begin
	 red = 8'hFF;
	 green = 8'h77;
	 blue = 8'hAA;
      end
   end
   
   video_sig_gen vsg
     (
      .clk_pixel_in(clk_pixel),
      .rst_in(sys_rst),
      .hcount_out(hcount_hdmi),
      .vcount_out(vcount_hdmi),
      .vs_out(vsync_hdmi),
      .hs_out(hsync_hdmi),
      .ad_out(active_draw_hdmi),
      .fc_out(frame_count_hdmi)
      );
   
   
      
   //three tmds_encoders (blue, green, red)
   //note green should have no control signal like red
   //the blue channel DOES carry the two sync signals:
   //  * control_in[0] = horizontal sync signal
   //  * control_in[1] = vertical sync signal

   tmds_encoder tmds_red(
			 .clk_in(clk_pixel),
			 .rst_in(sys_rst),
			 .data_in(red),
			 .control_in(2'b0),
			 .ve_in(active_draw_hdmi),
			 .tmds_out(tmds_10b[2]));

   tmds_encoder tmds_green(
			   .clk_in(clk_pixel),
			   .rst_in(sys_rst),
			   .data_in(green),
			   .control_in(2'b0),
			   .ve_in(active_draw_hdmi),
			   .tmds_out(tmds_10b[1]));

   tmds_encoder tmds_blue(
			  .clk_in(clk_pixel),
			  .rst_in(sys_rst),
			  .data_in(blue),
			  .control_in({vsync_hdmi,hsync_hdmi}),
			  .ve_in(active_draw_hdmi),
			  .tmds_out(tmds_10b[0]));
   
   
   //three tmds_serializers (blue, green, red):
   //MISSING: two more serializers for the green and blue tmds signals.
   tmds_serializer red_ser(
			   .clk_pixel_in(clk_pixel),
			   .clk_5x_in(clk_5x),
			   .rst_in(sys_rst),
			   .tmds_in(tmds_10b[2]),
			   .tmds_out(tmds_signal[2]));
   tmds_serializer green_ser(
			   .clk_pixel_in(clk_pixel),
			   .clk_5x_in(clk_5x),
			   .rst_in(sys_rst),
			   .tmds_in(tmds_10b[1]),
			   .tmds_out(tmds_signal[1]));
   tmds_serializer blue_ser(
			   .clk_pixel_in(clk_pixel),
			   .clk_5x_in(clk_5x),
			   .rst_in(sys_rst),
			   .tmds_in(tmds_10b[0]),
			   .tmds_out(tmds_signal[0]));
   
   //output buffers generating differential signals:
   //three for the r,g,b signals and one that is at the pixel clock rate
   //the HDMI receivers use recover logic coupled with the control signals asserted
   //during blanking and sync periods to synchronize their faster bit clocks off
   //of the slower pixel clock (so they can recover a clock of about 742.5 MHz from
   //the slower 74.25 MHz clock)
   OBUFDS OBUFDS_blue (.I(tmds_signal[0]), .O(hdmi_tx_p[0]), .OB(hdmi_tx_n[0]));
   OBUFDS OBUFDS_green(.I(tmds_signal[1]), .O(hdmi_tx_p[1]), .OB(hdmi_tx_n[1]));
   OBUFDS OBUFDS_red  (.I(tmds_signal[2]), .O(hdmi_tx_p[2]), .OB(hdmi_tx_n[2]));
   OBUFDS OBUFDS_clock(.I(clk_pixel), .O(hdmi_clk_p), .OB(hdmi_clk_n));
   
   // ====================== CHAPTER: REGISTER WRITES ===================

   logic       cr_init_valid, cr_init_ready;
   assign cr_init_valid = trigger_btn_camera;

   logic [23:0] bram_dout;
   logic [7:0] 	bram_addr;
   
   
   xilinx_single_port_ram_read_first
     #(
       .RAM_WIDTH(24),                       // Specify RAM data width
       .RAM_DEPTH(256),                     // Specify RAM depth (number of entries)
       .RAM_PERFORMANCE("HIGH_PERFORMANCE"), // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
       .INIT_FILE("rom.mem")          // Specify name/location of RAM initialization file if using one (leave blank if not)
       ) registers
       (
	.addra(bram_addr),     // Address bus, width determined from RAM_DEPTH
	.dina(24'b0),       // RAM input data, width determined from RAM_WIDTH
	.clka(clk_camera),       // Clock
	.wea(1'b0),         // Write enable
	.ena(1'b1),         // RAM Enable, for additional power savings, disable port when not in use
	.rsta(sys_rst),       // Output reset (does not affect memory contents)
	.regcea(1'b1),   // Output register enable
	.douta(bram_dout)      // RAM output data, width determined from RAM_WIDTH
	);

   logic [23:0] registers_dout;
   logic [7:0] 	registers_addr;
   assign registers_dout = bram_dout;
   assign bram_addr = registers_addr;
   
   logic       con_scl_i, con_scl_o, con_scl_t;
   logic       con_sda_i, con_sda_o, con_sda_t;

   // assign con_scl_i = pmodb_scl;
   // assign pmodb_scl = con_scl_o ? 1'bz : 0;

   // assign con_sda_i = pmodb_sda;
   // assign pmodb_sda = con_sda_o ? 1'bz : 0;

   // NOTE these also have pullup specified in the xdc file!
   IOBUF IOBUF_scl (.I(con_scl_o), .IO(pmodb_scl), .O(con_scl_i), .T(con_scl_t) );
   IOBUF IOBUF_sda (.I(con_sda_o), .IO(pmodb_sda), .O(con_sda_i), .T(con_sda_t) );

   logic       busy,bus_active;
   logic [3:0] ii_state;
   
   camera_registers crw
     (.clk_in(clk_camera),
      .rst_in(sys_rst),
      .init_valid(cr_init_valid),
      .init_ready(cr_init_ready),
      .scl_i(con_scl_i),
      .scl_o(con_scl_o),
      .scl_t(con_scl_t),
      .sda_i(con_sda_i),
      .sda_o(con_sda_o),
      .sda_t(con_sda_t),
      .bram_dout(registers_dout),
      .bram_addr(registers_addr),
      .busy(busy),
      .bus_active(bus_active),
      .state_out(ii_state));
   

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

   // CHAPTER: ASSEMBLY RECEIVER

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

   logic 	       mmio_uart_txd;
   
   uart_transmitter
     #(.BAUD_RATE(BAUD),
       .CLOCK_SPEED(100_000_000)) utm
       (.clk_in(sys_clk),
	.rst_in(sys_rst),
	.data_in(uart_tx_data),
	.valid_in(uart_tx_valid),
	.ready_in(uart_tx_ready),
	.uart_tx(mmio_uart_txd));
   
   logic 	       proc_reset;
   assign proc_reset = (sys_rst || ~proc_release);

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
   logic 	       processor_done;

   wrapped_processor processor
     (.clk_in(sys_clk),
      .rst_in(proc_reset), // processor is held at reset for longer than other components, so we can load memory in

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

      
   logic [127:0]       ui_req_axis_data;
   logic 	       ui_req_axis_tuser;
   logic 	       ui_req_axis_ready;
   logic 	       ui_req_axis_valid;

   logic [127:0]       ui_resp_axis_data;
   logic 	       ui_resp_axis_tuser;
   logic 	       ui_resp_axis_ready;
   logic 	       ui_resp_axis_valid;


   // pathway: processor request -> serialize -> clock domain cross -> channel merger
   

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

   // for the sake of syncing all potentially-used signals:
   logic 	hsync_cc;
   logic 	vsync_cc;
   always_ff @(posedge clk_camera) begin
      hsync_cc <= hsync;
      vsync_cc <= vsync;
   end

   
   logic [31:0] display_hcvc;
   display_hcount_vcount dm00
     (.clk_in(clk_camera),
      .rst_in(sys_rst),
      .hcount_in(hcount_cc),
      .vcount_in(vcount_cc),
      .hsync_in(hsync_cc),
      .vsync_in(vsync_cc),
      .display_out(display_hcvc)
      );

   
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
   assign val_to_display = btn[1] ? (btn[3] ? response_hold_chunks[offset] : debug_pc) : (btn[3] ? debug_lane : display_hcvc);
   

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

   logic 	       tm_write_axis_ready[4:0];
   logic 	       tm_write_axis_valid[4:0];
   logic [127:0]       tm_write_axis_data[4:0];
   logic 	       tm_write_axis_tuser[4:0];

   logic 	       tm_read_axis_ready[4:0];
   logic 	       tm_read_axis_valid[4:0];
   logic [127:0]       tm_read_axis_data[4:0];
   logic 	       tm_read_axis_tuser[4:0];
   logic 	       tm_read_axis_af[4:0];

   // CHANNEL 0: processor core requests+responses
   assign ui_req_axis_ready = tm_write_axis_ready[0];
   assign tm_write_axis_valid[0] = ui_req_axis_valid;
   assign tm_write_axis_data[0] = ui_req_axis_data;
   assign tm_write_axis_tuser[0] = ui_req_axis_tuser;

   assign tm_read_axis_ready[0] = ui_resp_axis_ready;
   assign ui_resp_axis_valid = tm_read_axis_valid[0];
   assign ui_resp_axis_data = tm_read_axis_data[0];
   assign tm_read_axis_af[0] = resp_axis_af;
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
   assign tm_read_axis_af[2] = ssc_resp_axis_af;
   assign ui_ssc_resp_axis_tuser = tm_read_axis_tuser[2];
   
   // CHANNEL 3: write camera data, read nothing ever
   assign tm_write_axis_data[3] = cam_write_axis_phrase;
   assign tm_write_axis_tuser[3] = cam_write_axis_tuser;
   assign tm_write_axis_valid[3] = cam_write_axis_valid;
   assign cam_write_axis_ready = tm_write_axis_ready[3];

   assign tm_read_axis_ready[3] = 1'b0;
   
   // CHANNEL 4: read hdmi data, write nothing ever
   channel_update read_cmd = {CAMERA_FB_ADDR, 27'((1280*720) >> 3), 1'b0};
   assign tm_write_axis_data[4] = read_cmd;
   assign tm_write_axis_tuser[4] = 1'b1;
   assign tm_write_axis_valid[4] = 1'b1;

   assign hdmi_resp_axis_data = tm_read_axis_data[4];
   assign tm_read_axis_ready[4] = hdmi_resp_axis_ready;
   assign hdmi_resp_axis_tuser = tm_read_axis_tuser[4];
   assign tm_read_axis_af[4] = hdmi_resp_axis_af;
   assign hdmi_resp_axis_valid = tm_read_axis_valid[4];
   
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

   traffic_merger #(.CHANNEL_COUNT(5)) tg
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

   logic [7:0] 	       probe_uart_tx_data;
   logic 	       probe_uart_tx_ready;
   logic 	       probe_uart_tx_valid;

   logic 	       probe_uart_txd;
   
   parsed_meta packet_meta;
   assign packet_meta.addr = app_addr[26:0];
   assign packet_meta.channel = tg.current_channel;
   assign packet_meta.wen = (app_wdf_wren);

   logic 	       probe_trigger, transmit_trigger;
   assign probe_trigger = btn[2];
   assign transmit_trigger = processor_done;
   
   pipe_probe probe
     (.clk_in(ui_clk),
      .rst_in(sys_rst),
      .probe_trigger_in(probe_trigger),
      .transmit_trigger_in(transmit_trigger),
      .uart_tx_data(probe_uart_tx_data),
      .uart_tx_ready(probe_uart_tx_ready),
      .uart_tx_valid(probe_uart_tx_valid),
      .packet_meta(packet_meta),
      .checkpointA_en( tg.command_success ),
      .checkpointB_en( app_rd_data_valid ),
      .id_a( tg.rqm.new_cmd_index ),
      .id_b( tg.rqm.next_rsp_index ));

   uart_transmitter
     #(.BAUD_RATE(BAUD),
       .CLOCK_SPEED(81_250_000)) probe_utm
       (.clk_in(ui_clk),
	.rst_in(sys_rst),
	.data_in(probe_uart_tx_data),
	.valid_in(probe_uart_tx_valid),
	.ready_in(probe_uart_tx_ready),
	.uart_tx(probe_uart_txd));

   assign uart_txd = sw[2] ? probe_uart_txd : mmio_uart_txd;
   
   
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
      .sys_clk_i(clk_camera),
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
   

   logic [7:0] 	       phrase_axis_valid_count;
   always_ff @(posedge sys_clk) begin
      if(sys_rst) begin
	 phrase_axis_valid_count <= 0;
      end else begin
	 phrase_axis_valid_count <= phrase_axis_valid_count + (phrase_axis_valid);
      end
   end

   assign led[0] = proc_reset;
   assign led[1] = init_calib_complete;
   assign led[2] = processor_done;

   assign led[4] = cr_init_valid;
   assign led[5] = valid_pixel;
   assign led[6] = valid_cc;
   assign led[7] = phrase_axis_valid;
   assign led[8] = cam_write_axis_valid;
   assign led[9] = tm_write_axis_valid[3];
   assign led[10] = trigger_btn_camera;
   assign led[11] = cr_init_ready;
   assign led[12] = busy;
   assign led[13] = bus_active;
   // assign led[15:14] = phrase_axis_valid_count;
   

endmodule
`default_nettype wire
