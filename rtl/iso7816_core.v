/*
 * iso7816_core.v
 *
 * vim: ts=4 sw=4
 *
 * ISO7816 Main logic core
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none

module iso7816_core #(
	parameter integer EXT_IOREG = 1
)(
	// IO
	input  wire io_i,
	output reg  io_o,
	output reg  io_oe,

	// TX data IF
	input  wire  [7:0] tx_data,
	input  wire        tx_valid,
	output reg         tx_ack,
	output reg   [1:0] tx_status,		// 00=ok, 01=ok,retried, 11=fail

	// RX data IF
	output wire  [7:0] rx_data,
	output reg         rx_stb,
	output reg   [1:0] rx_status,		// 00=ok, 01=ok,retried, 10=parity err, 11=frame err

	// Baud Rate Generator IF
	input  wire        brg_stb_tx,
	input  wire        brg_stb_rx,

	output wire        brg_txrx,
	output wire        brg_sync,
	output wire        brg_run,

	// Misc
	output wire        wt_clr,

	// Configuration
	input  wire        cfg_tx_ena,		// TX: enable
	input  wire        cfg_tx_nak,		// TX: Check for NAKs and retry
	input  wire  [2:0] cfg_tx_tries,	// TX: Max # of retries - 1 in case of NAK
	input  wire [11:0] cfg_tx_GT,		// TX: Guard Time

	input  wire        cfg_rx_ena,		// RX: enable
	input  wire        cfg_rx_nak,		// RX: NAK on error

	// Clock
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// FSM
	localparam
		ST_IDLE          = 0,
		ST_TX_START      = 1,
		ST_TX_BITS       = 2,
		ST_TX_STOP       = 3,
		ST_TX_CHECK      = 4,
		ST_TX_PAUSE      = 5,
		ST_RX_START      = 6,
		ST_RX_BITS       = 7,
		ST_RX_CHECK      = 8,
		ST_RX_NAK        = 9,
		ST_RX_STOP       = 10
		;

	reg [3:0] state;
	reg [3:0] state_nxt;

	// IO path
	reg  [1:0] io_i_sync;
	reg        io_i_fall;
	wire       io_i_val;

	// Shift Register
	wire       sr_in;
	wire       sr_load;
	wire       sr_ce;
	reg  [8:0] sr_data;
	wire       sr_parity;

	reg  [3:0] sr_bitcnt;
	wire       sr_bitcnt_last;

	// TX
	reg [11:0] tx_gt_timer;
	wire       tx_gt_ce;
	wire       tx_gt_dec;
	wire       tx_gt_ready;

	reg [ 3:0] tx_retry_cnt;
	reg        tx_retry_ce;
	reg        tx_retry_dec;
	wire       tx_retry_last;
	reg        tx_retried;

	// RX
	wire       rx_parity_ok;
	reg        rx_retried;


	// FSM
	// ---

	// State register
	always @(posedge clk)
	begin
		if (rst)
			state <= ST_IDLE;
		else
			state <= state_nxt;
	end

	// Next-State logic
	always @(*)
	begin
		// Default
		state_nxt = state;

		// Anything to do ?
		case (state)
			ST_IDLE:
				// First instant of falling edge -> Start RX
				if (cfg_rx_ena & io_i_fall)
					state_nxt = ST_RX_START;

				// Or start TX ?
					// Note that because tx_ack is registered, we're already
					// back to ST_IDLE before the user had the opportunity to
					// lower tx_valid. However the next brg_stb_tx isn't for
					// a few cycle so we're good.
				else if (cfg_tx_ena & tx_valid & tx_gt_ready & brg_stb_tx)
					state_nxt = ST_TX_START;

			ST_TX_START:
				if (brg_stb_tx)
					state_nxt = ST_TX_BITS;

			ST_TX_BITS:
				if (brg_stb_tx & sr_bitcnt_last)
					state_nxt = ST_TX_STOP;

			ST_TX_STOP:
				// TX force high for a short time.
				// One cycle would be enough but we wait for the RX stb
				// that immediate follows the TX strobe so the check is
				// on the next "moment"
				if (brg_stb_rx)
					state_nxt = ST_TX_CHECK;

			ST_TX_CHECK:
				if (brg_stb_rx)
					state_nxt = io_i_val ? ST_IDLE : ST_TX_PAUSE;

			ST_TX_PAUSE:
				// Error was detected, we need to wait one more ETU
				if (brg_stb_rx)
					state_nxt = ST_IDLE;

			ST_RX_START:
				// Validate "Start Moment"
				if (brg_stb_rx)
					state_nxt = io_i_val ? ST_IDLE : ST_RX_BITS;

			ST_RX_BITS:
				// Receive all data bits + parity bit
				if (brg_stb_rx & sr_bitcnt_last)
					state_nxt = ST_RX_CHECK;

			ST_RX_CHECK:
				// Check if a NAK is required
				if (~cfg_rx_nak || rx_parity_ok)
					state_nxt = ST_RX_STOP;
				else if (brg_stb_tx)
					state_nxt = ST_RX_NAK;

			ST_RX_NAK:
				// NAK is asserted
				if (brg_stb_tx)
					state_nxt = ST_IDLE;

			ST_RX_STOP:
				// Validate the "Stop Moment"
				if (brg_stb_rx)
					state_nxt = ST_IDLE;

		endcase
	end


	// Misc control
	// ------------

	// BRG Control
	assign brg_run  = 1'b1;
	assign brg_sync = (state == ST_IDLE) & io_i_fall;
	assign brg_txrx = 1'b0;	// RX

	// WT clear
	assign wt_clr = io_i_fall;


	// IO path
	// -------

	// If we have external IO reg, skip first reg
	if (EXT_IOREG)
		always @(*)
			io_i_sync[0] = io_i;
	else
		always @(posedge clk)
			io_i_sync[0] <= io_i;

	// Second synchronizer & Fall detect
	always @(posedge clk)
	begin
		io_i_sync[1] <=  io_i_sync[0];
		io_i_fall    <= ~io_i_sync[0] & io_i_sync[1];
	end

	assign io_i_val = io_i_sync[1];

	// Output
	always @(posedge clk)
	begin
		// Default is no output
		io_oe <= 1'b0;
		io_o  <= 1'bx;

		case (state)
			// If we're in RX NAK, assert to zero
			ST_RX_NAK: begin
				io_oe <= 1'b1;
				io_o  <= 1'b0;
			end

			// TX Start bit
			ST_TX_START: begin
				io_oe <= 1'b1;
				io_o  <= 1'b0;
			end

			// TX Data/Parity bits
			ST_TX_BITS: begin
				io_oe <= 1'b1;
				io_o  <= sr_data[0];
			end

			ST_TX_STOP: begin
				io_oe <= 1'b1;
				io_o  <= 1'b1;
			end
		endcase
	end


	// Shift register
	// --------------

	// Control
	assign sr_load = (state == ST_TX_START);
	assign sr_ce   = ((state == ST_RX_BITS) & brg_stb_rx) |
	                 ((state == ST_TX_BITS) & brg_stb_tx) |
	                 sr_load;

	// Shift
	always @(posedge clk)
		if (sr_ce)
			sr_data <= sr_load ?
				{ sr_parity, tx_data } :
				{ io_i_val, sr_data[8:1] };

	// Parity
	assign sr_parity = ^sr_data[7:0];

	// Bit counter
	always @(posedge clk)
		if ((state != ST_RX_BITS) && (state != ST_TX_BITS))
			sr_bitcnt <= 4'h7;
		else
			sr_bitcnt <= sr_bitcnt + {4{sr_ce}};

	assign sr_bitcnt_last = sr_bitcnt[3];


	// TX logic
	// --------

	// Guard time timer
	always @(posedge clk or posedge rst)
		if (rst)
			tx_gt_timer <= 0;
		else if (tx_gt_ce)
			tx_gt_timer <= tx_gt_dec ? (tx_gt_timer + {12{tx_gt_dec}}) : cfg_tx_GT;

	assign tx_gt_ce    = (state == ST_TX_START) | ((state == ST_IDLE) & ~tx_gt_ready & brg_stb_tx);
	assign tx_gt_dec   = (state == ST_IDLE);
	assign tx_gt_ready = tx_gt_timer[11];

	// Retry counter
	always @(posedge clk or posedge rst)
		if (rst)
			tx_retry_cnt <= 0;
		else if (tx_retry_ce)
			tx_retry_cnt <= tx_retry_dec ? (tx_retry_cnt + {4{tx_retry_dec}}) : { 1'b0, cfg_tx_tries };

	always @(posedge clk or posedge rst)
		if (rst)
			tx_retried <= 1'b0;
		else if (tx_retry_ce)
			tx_retried <= tx_retry_dec;

	always @(*)
	begin
		// Default is do nothing
		tx_retry_ce  = 1'b0;
		tx_retry_dec = 1'bx;

		// If no retry in progress, reload when IDLE
		// (to update config value)
		if ((state == ST_IDLE) & ~tx_retried) begin
			tx_retry_ce  = 1'b1;
			tx_retry_dec = 1'b0;
		end

		// Track success / fail
		else if ((state == ST_TX_CHECK) & brg_stb_rx) begin
			if (io_i_val) begin
				// ACK, we're good
				tx_retry_ce  = 1'b1;
				tx_retry_dec = 1'b0;
			end else if (tx_retry_last) begin
				// It was the last try and we got NAK'd
				tx_retry_ce  = 1'b1;
				tx_retry_dec = 1'b0;
			end else begin
				// Decrement for next attempt
				tx_retry_ce  = 1'b1;
				tx_retry_dec = 1'b1;
			end
		end
	end

	assign tx_retry_last = tx_retry_cnt[3];

	// External IF
	always @(posedge clk)
	begin
		// Default is nothing transmitted
		tx_ack    <= 1'b0;
		tx_status <= 2'bxx;

		// Is the NAK mechanism enabled ?
		if ((state == ST_TX_CHECK) & brg_stb_rx) begin
			if (cfg_tx_nak) begin
				if (io_i_val) begin
					// ACK, we're good
					tx_ack    <= 1'b1;
					tx_status <= { 1'b0, tx_retried };
				end else if (tx_retry_last) begin
					// It was the last try and we got NAK'd
					tx_ack    <= 1'b1;
					tx_status <= 2'b11;
				end
			end else begin
				// No NAK possible, so always ack when done
				tx_ack    <= 1'b1;
				tx_status <= 2'b00;
			end
		end
	end


	// RX logic
	// --------

	// Parity check
	assign rx_parity_ok = sr_parity == sr_data[8];

	// Track retries
	always @(posedge clk)
		if (rst)
			rx_retried <= 1'b0;
		else
			rx_retried <= (rx_retried | (state == ST_RX_NAK)) & ~((state == ST_RX_STOP) & brg_stb_rx);

	// External IF
	assign rx_data = sr_data[7:0];

	always @(posedge clk)
	begin
		// Default is nothing received
		rx_stb    <= 1'b0;
		rx_status <= 2'bxx;

		// Parity error
		if ((state == ST_RX_NAK) & brg_stb_tx) begin
			rx_stb    <= 1'b1;
			rx_status <= 2'b10;
		end

		// RX complete (but might still be parity / frame error)
		if ((state == ST_RX_STOP) & brg_stb_rx) begin
			rx_stb    <= 1'b1;
			if (~rx_parity_ok)
				// Have to check parity here since a NAK is only issued if NAK
				// are enabled
				rx_status <= 2'b10;
			else if (~io_i_val)
				// If the stop bit isn't one, frame error
				rx_status <= 2'b11;
			else
				// All good (although possibly got retried)
				rx_status <= { 1'b0, rx_retried };
		end
	end

endmodule // iso7816_core
