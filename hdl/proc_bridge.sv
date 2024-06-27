`timescale 1ns / 1ps
`default_nettype none

typedef struct packed {
   logic       write;
   logic [25:0] addr;
   logic [511:0] data;
} main_mem_req;

typedef struct packed {
   logic [3:0] byte_en;
   logic [31:0] addr;
   logic [31:0] data;
} mmio_mem;

`ifndef CHANNEL_UPDATE
 `define CHANNEL_UPDATE
typedef struct packed {
   logic [26:0] addr;
   logic [26:0] stream_length;
   logic 	wen;
} channel_update;
`endif

module serialize_req
  (
   input wire 		clk_in,
   input wire 		rst_in,
   output logic 	getMReq_en,
   input wire 		getMReq_rdy,
   input wire [538:0] 	getMReq_data,
   output logic [127:0] req_axis_data,
   output logic 	req_axis_tuser,
   input wire 		req_axis_ready,
   output logic 	req_axis_valid,
   output logic [1:0] 	srstate);

   typedef enum 	{READY, TUSER, DATA} sr_state;
   sr_state state;
   assign srstate = state;

   main_mem_req memReq;
   channel_update translateReq;
   assign translateReq.wen = memReq.write;
   assign translateReq.stream_length = 26'h4;
   assign translateReq.addr = memReq.addr << 2;

   logic 		accept_in;
   logic 		accept_out;
   assign accept_in = (getMReq_en && getMReq_rdy);
   assign getMReq_en = (getMReq_rdy && state == READY);
   assign accept_out = (req_axis_ready && req_axis_valid);

   logic [127:0] 	data_chunks[3:0];
   assign data_chunks[0] = memReq.data[127:0];
   assign data_chunks[1] = memReq.data[255:128];
   assign data_chunks[2] = memReq.data[383:256];
   assign data_chunks[3] = memReq.data[511:384];
   

   logic [1:0] 		index;
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 state <= READY;
	 memReq <= 539'b0;
	 index <= 0;
      end else begin
	 case (state)
	   READY: begin
	      if (accept_in) begin
		 state <= TUSER;
		 memReq <= getMReq_data;
		 index <= 0;
	      end
	   end
	   TUSER: begin
	      if (accept_out) begin
		 $display("[srm rx] addr=%x write=%d",memReq.addr,memReq.write);
		 $display("[srm tx] addr=%x sl=%x wen=%d",translateReq.addr,translateReq.stream_length,translateReq.wen);
		 
		 state <= translateReq.wen ? DATA : READY;
		 index <= 0;
		 // $stop;
	      end
	   end
	   DATA: begin
	      if (accept_out) begin
		 if (index == 3) begin
		    state <= READY;
		    index <= 0;
		 end else begin
		    index <= index + 1;

		 end
	      end
	   end
	 endcase // case (state)
      end
   end // always_ff @ (posedge clk_in)

   always_comb begin
      case(state)
	READY: begin
	   req_axis_data = 0;
	   req_axis_tuser = 0;
	   req_axis_valid = 0;
	end
	TUSER: begin
	   req_axis_data = translateReq;
	   req_axis_tuser = 1;
	   req_axis_valid = 1;
	end
	DATA: begin
	   req_axis_data = data_chunks[index];
	   req_axis_tuser = 0;
	   req_axis_valid = 1;
	end
      endcase
   end

endmodule // send_req


module accumulate_resp
  (
   input wire 		clk_in,
   input wire 		rst_in,
   input wire [127:0] 	resp_axis_data,
   input wire 		resp_axis_valid,
   input wire 		resp_axis_tuser,
   output logic 	resp_axis_ready,
   output logic [511:0] putMResp_data,
   output logic 	putMResp_en,
   input wire 		putMResp_rdy);

   logic [127:0] 	response_pieces[3:0];
   assign putMResp_data = { response_pieces[3], response_pieces[2], response_pieces[1], response_pieces[0]};

   logic [1:0] 		index;
   logic 		index_rollover;

   logic 		phrase_taken;

   logic 		accept_resp_axis;
   logic 		accept_putMResp;
   assign accept_resp_axis = (resp_axis_valid && resp_axis_ready);
   assign resp_axis_ready = phrase_taken;
   
   assign accept_putMResp = (putMResp_en && putMResp_rdy);
   assign putMResp_en = putMResp_rdy && (index_rollover || ~phrase_taken);

   cursor #(.WIDTH(2),.ROLLOVER(4)) index_cursor
     (.clk_in(clk_in),
      .rst_in(rst_in),
      .incr_in(accept_resp_axis),
      .cursor_out(index),
      .rollover_out(index_rollover));
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 phrase_taken <= 1'b1;
      end else begin
	 if (accept_resp_axis) begin
	    response_pieces[index] <= resp_axis_data;
	 end
	 if (index == 3 || ~phrase_taken) begin
	    phrase_taken <= putMResp_rdy;
	 end
      end
   end

endmodule // build_resp

module handle_mmio
  (
   input wire 	       clk_in,
   input wire 	       rst_in,

   output logic        getMMIOReq_en,
   input wire 	       getMMIOReq_rdy,
   input wire [67:0]   getMMIOReq_data,

   output logic        putMMIOResp_en,
   input wire 	       putMMIOResp_rdy,
   output logic [67:0] putMMIOResp_data,

   output logic [7:0]  uart_tx_data,
   input wire 	       uart_tx_ready,
   output logic        uart_tx_valid,
   
   output logic        processor_done
   );

   typedef enum        {READY, BUSY, RETURN} mmiostate;
   mmiostate mstate;

   typedef enum        {PUTCHAR,FINISH} mmiotype;
   mmiotype current_mtype;

   mmio_mem mmio_in, mmio_hold;
   assign mmio_in = getMMIOReq_data;

   assign getMMIOReq_en = (getMMIOReq_rdy && mstate == READY);
   assign putMMIOResp_en = (putMMIOResp_rdy && mstate == RETURN);

   assign uart_tx_data = (mstate == BUSY && current_mtype == PUTCHAR) ? mmio_hold.data[7:0] : 8'b0;
   assign uart_tx_valid = (mstate == BUSY && current_mtype == PUTCHAR);

   assign putMMIOResp_data = putMMIOResp_en ? mmio_hold : 0;

   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 mstate <= READY;
	 processor_done <= 1'b0;
	 mmio_hold <= 0;
      end else begin
	 case(mstate)
	   READY: begin
	      if (getMMIOReq_en) begin
		 mstate <= BUSY;
		 mmio_hold <= mmio_in;
		 current_mtype <= (mmio_in.addr == 32'hFFF8) ? FINISH : PUTCHAR;
	      end
	   end
	   BUSY: begin
	      if (current_mtype == PUTCHAR && uart_tx_valid && uart_tx_ready) begin
		 mstate <= RETURN;
	      end
	      if (current_mtype == FINISH) begin
		 processor_done <= 1'b1;
		 mstate <= RETURN;
	      end
	   end
	   RETURN: begin
	      if (putMMIOResp_en) begin
		 mstate <= READY;
	      end
	   end
	 endcase
      end
   end
   
   
   
endmodule // handle_mmio



`default_nettype wire
