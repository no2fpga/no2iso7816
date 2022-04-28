/*
 * iso7816_core_tb.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`timescale 1 ns / 100 ps
`default_nettype none

module iso7816_core_tb;

	// Signals
	// -------

	wire io_i;
	wire io_o;
	wire io_oe;

	wire  [7:0] tx_data;
	wire        tx_valid;
	wire        tx_ack;
	wire  [1:0] tx_status;

	wire  [7:0] rx_data;
	wire        rx_stb;
	wire  [1:0] rx_status;

	wire        brg_stb_tx;
	wire        brg_stb_rx;
	wire        brg_txrx;
	wire        brg_sync;
	wire        brg_run;

	wire [14:0] cfg_Fs;
	wire [14:0] cfg_Ds_n;
	wire [14:0] cfg_init;

	wire        cfg_tx_ena;
	wire        cfg_tx_nak;
	wire  [2:0] cfg_tx_tries;
	wire [11:0] cfg_tx_GT;

	wire        cfg_rx_ena;
	wire        cfg_rx_nak;

	reg  clk_sys  = 1'b0;
	reg  clk_uart = 1'b0;
	reg  rst      = 1'b1;


	// DUT
	// ---

	// Core
	iso7816_core #(
		.EXT_IOREG(1)
	) dut_core_I (
		.io_i         (io_i),
		.io_o         (io_o),
		.io_oe        (io_oe),
		.tx_data      (tx_data),
		.tx_valid     (tx_valid),
		.tx_ack       (tx_ack),
		.tx_status    (tx_status),
		.rx_data      (rx_data),
		.rx_stb       (rx_stb),
		.rx_status    (rx_status),
		.brg_stb_tx   (brg_stb_tx),
		.brg_stb_rx   (brg_stb_rx),
		.brg_txrx     (brg_txrx),
		.brg_sync     (brg_sync),
		.brg_run      (brg_run),
		.wt_clr       (),
		.cfg_tx_ena   (cfg_tx_ena),
		.cfg_tx_nak   (cfg_tx_nak),
		.cfg_tx_tries (cfg_tx_tries),
		.cfg_tx_GT    (cfg_tx_GT),
		.cfg_rx_ena   (cfg_rx_ena),
		.cfg_rx_nak   (cfg_rx_nak),
		.clk          (clk_sys),
		.rst          (rst)
	);

	// BRG
	iso7816_brg_sync #(
		.TXRX_LAG(3),
		.W(15)
	) dut_brg_I (
		.stb_tx   (brg_stb_tx),
		.stb_rx   (brg_stb_rx),
		.txrx     (brg_txrx),
		.sync     (brg_sync),
		.run      (brg_run),
		.cfg_Fs   (cfg_Fs),
		.cfg_Ds_n (cfg_Ds_n),
		.cfg_init (cfg_init),
		.clk      (clk_sys),
		.rst      (rst)
	);


	// Stimulus
	// --------

	// Config
	assign cfg_Fs       =  15'd372;
	assign cfg_Ds_n     = ~15'd32;
	assign cfg_init     =  15'd58;		// 372/2 - 4*32

	assign cfg_rx_ena   = 1'b1;
	assign cfg_rx_nak   = 1'b1;

	assign cfg_tx_ena   = 1'b1;
	assign cfg_tx_nak   = 1'b1;
	assign cfg_tx_tries = 3'd3;
	assign cfg_tx_GT    = 12'h800;

	// UART

		// 'H' 0x48 correct
		// 'a' 0x61 correct
		// 'a' 0x61 bad parity
		// 'x' 0x78 frame error

		// Idle | B Data     P E | B Data     P E | Idle | B Data     P E | Idle | B Data     P E | Idle |
		// 1111   0 00010010 0 1   0 10000110 1 1   1111   0 10000110 0 1   1      0 00011110 0 0   111
	reg [55:0] data = 56'b11110000100100101000011011111101000011001100001111000111;

	always @(posedge clk_uart)
		if (~rst)
			data <= { data[54:0], data[55] };

	assign io_i = 1'b1; // data[0];

	assign tx_data  = 8'ha6;
	assign tx_valid = 1'b1;


	// Test bench
	// ----------

	// Setup recording
	initial begin
		$dumpfile("iso7816_core_tb.vcd");
		$dumpvars(0,iso7816_core_tb);
	end

	// Reset pulse
	initial begin
		# 200 rst = 0;
		# 1000000 $finish;
	end

	// Clocks
	always  #25 clk_sys  = ~clk_sys;		// 20 MHz
	always #290 clk_uart = ~clk_uart;		// ~1.7 Mbaud (not a real rate ... but matches selected Fs/Ds)

endmodule // iso7816_core_tb
