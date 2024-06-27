`timescale 1ns / 1ps
`default_nettype none

module uart_transmitter
  #(parameter BAUD_RATE = 25_000_000,
    parameter CLOCK_SPEED = 100_000_000)
   (input wire clk_in,
    input wire 	     rst_in,
    input wire [7:0] data_in,
    input wire 	     valid_in,
    output logic     ready_in,
    output logic     uart_tx);

   localparam PERIOD_CYCLES = CLOCK_SPEED / BAUD_RATE;
   
   typedef enum      {IDLE, TRANSMIT} uart_tx_state;
   uart_tx_state state;

   logic [7:0] 	     current_data;
   logic [9:0] 	     frame;
   assign frame[0] = 1'b0; // START bit
   assign frame[8:1] = current_data;
   assign frame[9] = 1'b1; // STOP big

   logic [3:0] 	     index;
   logic [$clog2(PERIOD_CYCLES):0] cycle_count;

   assign uart_tx = (state == TRANSMIT) ? frame[index] : 1'b1; // idle high
   assign ready_in = (state == IDLE);
   
   always_ff @(posedge clk_in) begin
      if (rst_in) begin
	 current_data <= 8'b0;
	 state <= IDLE;
	 index <= 0;
	 cycle_count <= 0;
      end else begin
	 case(state)
	   IDLE: begin
	      if (valid_in) begin
		 current_data <= data_in;
		 state <= TRANSMIT;
		 index <= 0;
		 cycle_count <= PERIOD_CYCLES-1;
	      end
	   end
	   TRANSMIT: begin
	      if (cycle_count == 0) begin
		 if (index == 9) begin
		    state <= IDLE;
		 end else begin
		    cycle_count <= PERIOD_CYCLES-1;
		    index <= index + 1;
		 end
	      end else begin
		 cycle_count <= cycle_count - 1;
	      end
	   end
	 endcase
      end
   end

endmodule
`default_nettype wire
