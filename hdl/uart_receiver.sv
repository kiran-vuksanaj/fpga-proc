`timescale 1ns / 1ps
`default_nettype none

module uart_rcv
  #(parameter BAUD_RATE = 9600,
    parameter CLOCK_SPEED = 100_000_000
    )
   (input wire clk_in,
    input wire 	       rst_in,
    input wire 	       uart_rx,
    output logic       valid_out,
    output logic [7:0] data_out,
    // debugging
    output logic [2:0] ustate
    );

   localparam PERIOD_CYCLES = CLOCK_SPEED / BAUD_RATE;
   localparam READ_POINT = PERIOD_CYCLES / 2;

   typedef enum  {IDLE,START,READ,STOP,TRANSMIT} uart_state;
   uart_state state;
   assign ustate = state;
   
   logic [3:0] 	 index;

   assign valid_out = (state == TRANSMIT);

   logic [$clog2(PERIOD_CYCLES):0] cycle_count;

   // frame including start and stop bits
   logic [9:0] 			   uart_frame;
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 state <= IDLE;
	 cycle_count <= 0;
	 index <= 0;
      end else begin

	 case(state)
	   IDLE: begin
	      if (~uart_rx) begin
		 state <= START;
		 index <= 0;
		 cycle_count <= PERIOD_CYCLES-1;
		 uart_frame <= 10'b0;
	      end
	   end
	   START: begin
	      if (cycle_count == 0) begin
		 cycle_count <= PERIOD_CYCLES-1;
		 index <= index + 1;
		 state <= READ;
	      end else begin
		 cycle_count <= cycle_count - 1;
		 if (cycle_count == READ_POINT) begin
		    // ensure start bit is still a zero, send back to idle otherwise
		    state <= (uart_rx == 1'b0) ? START : IDLE;
		    uart_frame[index] <= uart_rx;
		 end
	      end
	   end
	   READ: begin

	      if (cycle_count == 0) begin
		 // baud cycle completed--read value
		 cycle_count <= PERIOD_CYCLES-1;
		 index <= index + 1;
		 if (index == 8) begin
		    state <= STOP;
		 end
	      end else begin
		 // count down cycles
		 cycle_count <= cycle_count - 1;

		 if (cycle_count == READ_POINT) begin
		    // write data as currently seen, at center of period
		    uart_frame[index] <= uart_rx;
		 end
	      end

	   end // case: READ
	   STOP: begin
	      // wait one baud period during the stop bit
	      if (cycle_count == 0) begin
		 if (uart_frame[9] == 1'b1) begin
		    // valid stop bit read, ready to transmit
		    state <= TRANSMIT;
		    data_out <= uart_frame[8:1];
		 end else begin
		    // if uart_frame[9] is something other than 1, then we failed to read properly
		    state <= IDLE;
		 end
	      end else begin
		 if (cycle_count == READ_POINT) begin
		    uart_frame[index] <= uart_rx;
		 end
		 cycle_count <= cycle_count - 1;
	      end
	   end
	   TRANSMIT: begin
	      // only stay here for 1 cycle
	      state <= IDLE;
	   end
	 endcase // case (state)
	 
      end
   end

endmodule

`default_nettype wire
