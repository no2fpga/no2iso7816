/*
 * iso7816_brg_sync_tb.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`timescale 1 ns / 100 ps
`default_nettype none

module iso7816_brg_sync_tb;

	// Signals
	// -------

	wire stb_tx;
	wire stb_rx;

	wire txrx;
	wire sync;
	wire run;

	wire [14:0] cfg_Fs;
	wire [14:0] cfg_Ds_n;
	wire [14:0] cfg_init;

	reg  [8:0] cnt;

	reg  clk = 1'b0;
	reg  rst = 1'b1;


	// DUT
	// ---

	iso7816_brg_sync #(
		.TXRX_LAG(3),
		.W(15)
	) dut_I (
		.stb_tx   (stb_tx),
		.stb_rx   (stb_rx),
		.txrx     (txrx),
		.sync     (sync),
		.run      (run),
		.cfg_Fs   (cfg_Fs),
		.cfg_Ds_n (cfg_Ds_n),
		.cfg_init (cfg_init),
		.clk      (clk),
		.rst      (rst)
	);


	// Stimulus
	// --------

	always @(posedge clk)
		if (rst)
			cnt <= 0;
		else
			cnt <= cnt + 1;

	assign txrx = 1'b0;
	assign sync = (cnt == 100);
	assign run  = (cnt > 100);

	assign cfg_Fs   =  15'd372;
	assign cfg_Ds_n = ~15'd32;
	assign cfg_init =  15'd58;		// 372/2 - 4*32

	//assign cfg_Fs   =  15'd1488;
	//assign cfg_Ds_n = ~15'd1;
	//assign cfg_init =  15'd740;


	// Test bench
	// ----------

	// Setup recording
	initial begin
		$dumpfile("iso7816_brg_sync_tb.vcd");
		$dumpvars(0,iso7816_brg_sync_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always #100 clk = !clk;

endmodule // iso7816_brg_sync_tb
