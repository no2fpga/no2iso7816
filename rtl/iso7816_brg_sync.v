/*
 * iso7816_brg_sync.v
 *
 * vim: ts=4 sw=4
 *
 * ISO7816 Baud Rate generator synchronous to system clock
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none

module iso7816_brg_sync #(
	parameter integer TXRX_LAG = 0,
	parameter integer W = 15
)(
	// Output
	output wire stb_tx,
	output wire stb_rx,

	// Control
	input  wire txrx,				// 0=rx / 1=tx
	input  wire sync,
	input  wire run,

	// Configuration
	input  wire [W-1:0] cfg_Fs,
	input  wire [W-1:0] cfg_Ds_n,		// Pre-inverted
	input  wire [W-1:0] cfg_init,

	// Clock
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	(* keep *) reg          c_fb_ena;
	(* keep *) reg  [  1:0] c_k_sel;
	(* keep *) reg          c_zero_n;

	wire [W  :0] acc_fb_add;	// feedback adder
	wire [W-1:0] acc_k_mux;		// constant mux
	wire [W  :0] acc_nxt;		// final adder
	reg  [W  :0] acc;


	// Accumulator
	// -----------

	assign acc_fb_add = c_fb_ena ? (acc + {cfg_Ds_n[W-1], cfg_Ds_n}) : {cfg_Ds_n[W-1], cfg_Ds_n};
	assign acc_k_mux  = (c_k_sel[0] ? cfg_init : cfg_Fs) & {W{c_k_sel[1]}};
	assign acc_nxt = (acc_fb_add + {1'b0, acc_k_mux } + 1'b1) & {(W+1){c_zero_n}};

	always @(posedge clk)
		if (rst)
			acc <= 0;
		else
			acc <= acc_nxt;


	// Strobes
	// -------

	// TX is direct
	assign stb_tx = acc[W];

	// RX lags (maybe)
	generate
		if (TXRX_LAG) begin
			// Use a simple chain of register
			reg [TXRX_LAG-1:0] stb_delay;

			always @(posedge clk)
				if (sync)
					stb_delay <= 0;
				else
					stb_delay <= { stb_delay[TXRX_LAG-2:0], stb_tx };

			assign stb_rx = stb_delay[TXRX_LAG-1];
		end else begin
			// Same pulse
			assign stb_rx = stb_tx;
		end
	endgenerate


	// Control
	// -------

	always @(*)
	begin
		// Default value
		c_fb_ena <= 1'bx;
		c_k_sel  <= 2'bxx;
		c_zero_n <= 1'b0;

		// Running ?
		if (sync) begin
			// Start
			c_fb_ena <= 1'b0;
			c_k_sel  <= txrx ? 2'b0x : 2'b11;
			c_zero_n <= 1'b1;
		end else if (run) begin
			c_fb_ena <= 1'b1;
			c_k_sel  <= acc[W] ? 2'b10 : 2'b0x;
			c_zero_n <= 1'b1;
		end
	end

endmodule // iso7816_brg_sync
