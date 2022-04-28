/*
 * iso7816_wb.v
 *
 * vim: ts=4 sw=4
 *
 * ISO7816 Wishbone variant
 *
 * Copyright (C) 2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none

module iso7816_wb #(
	parameter integer EXT_IOREG = 1,
	parameter integer WITH_WT = 1
)(
	// IO
	input  wire io_i,
	output reg  io_o,
	output reg  io_oe,

	// Wishbone slave
	input  wire [ 7:0] wb_addr,
	output reg  [31:0] wb_rdata,
	input  wire [31:0] wb_wdata,
	input  wire        wb_we,
	input  wire        wb_cyc,
	output reg         wb_ack,

	// IRQ
	output reg  irq,

	// Common
	input  wire clk,
	input  wire rst
);

	// Signals
	// -------

	// Bus
	wire        bus_rd_clr;
	wire        bus_wr_clr;

	wire [31:0] bus_rd_csr;
	wire [31:0] bus_rd_fifo;

	reg         bus_we_csr;
	reg         bus_we_data;
	reg         bus_we_cfg;
	reg         bus_we_wt;
	reg         bus_we_brg_rate;
	reg         bus_we_brg_phase;

	reg         bus_re_data;

	// TX data IF
	wire  [7:0] tx_data;
	wire        tx_valid;
	wire        tx_ack;
	wire  [1:0] tx_status;

	// RX data IF
	wire  [7:0] rx_data;
	wire        rx_stb;
	wire  [1:0] rx_status;

	// BRG
	wire        brg_stb_tx;
	wire        brg_stb_rx;
	wire        brg_txrx;
	wire        brg_sync;
	wire        brg_run;

	// Error tracking
	reg         tx_ef_parity;
	wire        tx_ef_parity_clr;

	reg         rx_ef_parity;
	wire        rx_ef_parity_clr;

	reg         rx_ef_frame;
	wire        rx_ef_frame_clr;

	// Configuration
	reg  [14:0] cfg_Fs;
	reg  [14:0] cfg_Ds_n;
	reg  [14:0] cfg_init;

	reg         cfg_wt_ie;
	reg  [22:0] cfg_wt_WT;

	reg  [11:0] cfg_tx_GT;
	reg   [2:0] cfg_tx_tries;
	reg         cfg_tx_irq_exc;
	reg         cfg_tx_irq_fifo;
	reg         cfg_tx_nak;
	reg         cfg_tx_ena;

	reg         cfg_rx_irq_exc;
	reg         cfg_rx_irq_fifo;
	reg         cfg_rx_nak;
	reg         cfg_rx_ena;

	// TX FIFO
	wire [7:0] txf_wdata;
	wire       txf_we;
	wire       txf_full;
	wire [7:0] txf_rdata;
	wire       txf_re;
	wire       txf_empty;

	reg        txf_overflow;
	wire       txf_overflow_clr;
	reg        txf_clear;
	wire       txf_clear_set;

	// RX FIFO
	wire [7:0] rxf_wdata;
	wire       rxf_we;
	wire       rxf_full;
	wire [7:0] rxf_rdata;
	wire       rxf_re;
	wire       rxf_empty;

	reg        rxf_overflow;
	wire       rxf_overflow_clr;
	reg        rxf_clear;
	wire       rxf_clear_set;

	// Wait timer
	wire       wt_clr_bus;
	wire       wt_clr_core;

	reg [23:0] wt_timer;
	wire       wt_dec;
	wire       wt_ce;
	wire       wt_expired;


	// Bus access
	// ----------

	// Ack
	always @(posedge clk)
		wb_ack <= wb_cyc & ~wb_ack;

	// Control
	assign bus_rd_clr = ~wb_cyc | wb_ack |  wb_we;
	assign bus_wr_clr = ~wb_cyc | wb_ack | ~wb_we;

	// Write strobes
	always @(posedge clk)
		if (bus_wr_clr) begin
			bus_we_csr       <= 1'b0;
			bus_we_data      <= 1'b0;
			bus_we_cfg       <= 1'b0;
			bus_we_wt        <= 1'b0;
			bus_we_brg_rate  <= 1'b0;
			bus_we_brg_phase <= 1'b0;
		end else begin
			bus_we_csr       <= wb_addr[2:0] == 3'h0;
			bus_we_data      <= wb_addr[2:0] == 3'h2;
			bus_we_cfg       <= wb_addr[2:0] == 3'h4;
			bus_we_wt        <= wb_addr[2:0] == 3'h5;
			bus_we_brg_rate  <= wb_addr[2:0] == 3'h6;
			bus_we_brg_phase <= wb_addr[2:0] == 3'h7;
		end

	// Read strobes
	always @(posedge clk)
		if (bus_rd_clr) begin
			bus_re_data      <= 1'b0;
		end else begin
			bus_re_data      <= wb_addr[2:0] == 3'h2;
		end

	// Read mux
	always @(posedge clk)
		if (bus_rd_clr)
			wb_rdata <= 32'h00000000;
		else
			wb_rdata <= wb_addr[1] ? bus_rd_fifo : bus_rd_csr;

	assign bus_rd_csr = {
		15'h0000,		// [31:17]

		wt_expired,		//    [16]

		txf_empty,		//    [15]
		txf_full,		//    [14]
		txf_overflow,	//    [13]
		txf_clear,		//    [12]
		tx_ef_parity,	//    [11]
		2'b00,			// [10: 9]
		cfg_tx_ena,		//     [8]

		rxf_empty,		//     [7]
		rxf_full,		//     [6]
		rxf_overflow,	//     [5]
		rxf_clear,		//     [4]
		rx_ef_parity,	//     [3]
		rx_ef_frame,	//     [2]
		1'b0,			//     [1]
		cfg_rx_ena		//     [0]
	};

	assign bus_rd_fifo = {
		rxf_empty,		//    [31]
		23'h000000,		// [30: 8]
		rxf_rdata		// [ 7: 0]
	};

	// Registers
	always @(posedge clk)
	begin
		// csr
		if (bus_we_csr) begin
			cfg_tx_ena <= wb_wdata[ 8];
			cfg_rx_ena <= wb_wdata[ 0];
		end

			// special handling: Disable TX on FAIL
		if (tx_ack & (tx_status == 2'b11))
			cfg_tx_ena <= 1'b0;

		// cfg 0x04
		if (bus_we_cfg) begin
			cfg_tx_GT       <= wb_wdata[31:20];
			cfg_tx_tries    <= wb_wdata[18:16];
			cfg_tx_irq_exc  <= wb_wdata[10];
			cfg_tx_irq_fifo <= wb_wdata[ 9];
			cfg_tx_nak      <= wb_wdata[ 8];
			cfg_rx_irq_exc  <= wb_wdata[ 2];
			cfg_rx_irq_fifo <= wb_wdata[ 1];
			cfg_rx_nak      <= wb_wdata[ 0];
		end

		// wt 0x05
		if (bus_we_wt) begin
			cfg_wt_ie <= wb_wdata[31];
			cfg_wt_WT <= wb_wdata[22:0];
		end

		// brg_rate 0x06
		if (bus_we_brg_rate) begin
			cfg_Fs   <= wb_wdata[30:16];
			cfg_Ds_n <= { 3'b111, ~wb_wdata[11:0] };
		end

		// brg_phase 0x07
		if (bus_we_brg_phase) begin
			cfg_init <= wb_wdata[14:0];
		end
	end

	assign wt_clr_bus       = bus_we_csr & wb_wdata[16];

	assign tx_ef_parity_clr = bus_we_csr & wb_wdata[11];
	assign rx_ef_parity_clr = bus_we_csr & wb_wdata[ 3];
	assign rx_ef_frame_clr  = bus_we_csr & wb_wdata[ 2];

	assign txf_overflow_clr = bus_we_csr & wb_wdata[13];
	assign txf_clear_set    = bus_we_csr & wb_wdata[12];

	assign rxf_overflow_clr = bus_we_csr & wb_wdata[ 5];
	assign rxf_clear_set    = bus_we_csr & wb_wdata[ 4];


	// Core
	// ----

	// Main logic
	iso7816_core #(
		.EXT_IOREG (EXT_IOREG)
	) core_I (
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
		.wt_clr       (wt_clr_core),
		.cfg_tx_ena   (cfg_tx_ena),
		.cfg_tx_nak   (cfg_tx_nak),
		.cfg_tx_tries (cfg_tx_tries),
		.cfg_tx_GT    (cfg_tx_GT),
		.cfg_rx_ena   (cfg_rx_ena),
		.cfg_rx_nak   (cfg_rx_nak),
		.clk          (clk),
		.rst          (rst)
	);

	// BRG
	iso7816_brg_sync #(
		.TXRX_LAG(EXT_IOREG ? 3 : 1),
		.W(15)
	) brg_I (
		.stb_tx   (brg_stb_tx),
		.stb_rx   (brg_stb_rx),
		.txrx     (brg_txrx),
		.sync     (brg_sync),
		.run      (brg_run),
		.cfg_Fs   (cfg_Fs),
		.cfg_Ds_n (cfg_Ds_n),
		.cfg_init (cfg_init),
		.clk      (clk),
		.rst      (rst)
	);


	// TX FIFO
	// -------

	// Instance
	fifo_sync_ram #(
		.DEPTH (512),
		.WIDTH (8)
	) tx_fifo_I (
		.wr_data  (txf_wdata),
		.wr_ena   (txf_we),
		.wr_full  (txf_full),
		.rd_data  (txf_rdata),
		.rd_ena   (txf_re),
		.rd_empty (txf_empty),
		.clk      (clk),
		.rst      (rst)
	);

	// Write from Bus
	assign txf_wdata = wb_wdata[7:0];
	assign txf_we    = bus_we_data & ~txf_full;

	// Read on TX
	assign tx_data  =  txf_rdata;
	assign tx_valid = ~txf_empty;

	assign txf_re = ((tx_ack & ~tx_status[1]) | txf_clear) & ~txf_empty;

	// Overflow logic
	always @(posedge clk)
		if (rst)
			txf_overflow <= 1'b0;
		else
			txf_overflow <= (txf_overflow & ~txf_overflow_clr) | (bus_we_data & txf_full);

	// Clear logic
	always @(posedge clk)
		if (rst)
			txf_clear <= 1'b0;
		else
			txf_clear <= (txf_clear & ~txf_empty) | txf_clear_set;


	// RX FIFO
	// -------

	// Instance
	fifo_sync_ram #(
		.DEPTH (512),
		.WIDTH (8)
	) rx_fifo_I (
		.wr_data  (rxf_wdata),
		.wr_ena   (rxf_we),
		.wr_full  (rxf_full),
		.rd_data  (rxf_rdata),
		.rd_ena   (rxf_re),
		.rd_empty (rxf_empty),
		.clk      (clk),
		.rst      (rst)
	);

	// Write on RX
	assign rxf_wdata = rx_data;
	assign rxf_we = rx_stb & ~rx_status[1] & ~rxf_full;

	// Read from Bus
	assign rxf_re = ((bus_re_data & ~wb_rdata[31]) | rxf_clear) & ~rxf_empty;

	// Overflow logic
	always @(posedge clk)
		if (rst)
			rxf_overflow <= 1'b0;
		else
			rxf_overflow <= (rxf_overflow & ~rxf_overflow_clr) | (rx_stb & ~rx_status[1] & rxf_full);

	// Clear logic
	always @(posedge clk)
		if (rst)
			rxf_clear <= 1'b0;
		else
			rxf_clear <= (rxf_clear & ~rxf_empty) | rxf_clear_set;


	// Error tracking
	// --------------

	always @(posedge clk)
		if (rst) begin
			tx_ef_parity <= 1'b0;
			rx_ef_parity <= 1'b0;
			rx_ef_frame  <= 1'b0;
		end else begin
			tx_ef_parity <= (tx_ef_parity & ~tx_ef_parity_clr) | (tx_ack & (tx_status == 2'b11));
			rx_ef_parity <= (rx_ef_parity & ~rx_ef_parity_clr) | (rx_stb & (rx_status == 2'b10));
			rx_ef_frame  <= (rx_ef_frame  & ~rx_ef_frame_clr)  | (rx_stb & (rx_status == 2'b11));
		end


	// Timeout timer
	// -------------

	// Optional
	if (WITH_WT) begin

		// Counter
		always @(posedge clk)
			if (wt_ce)
				wt_timer <= wt_dec ? (wt_timer + {24{wt_dec}}) : { 1'b0, cfg_wt_WT };

		// Control
			// Decrement if not expired and rx_strobe
			// Reload on manual clear, tx_ack, rx_ack
		assign wt_ce      = (~wt_expired & brg_stb_rx) | wt_clr_bus | wt_clr_core;
		assign wt_dec     = ~(wt_clr_bus | wt_clr_core);
		assign wt_expired = wt_timer[23];

	end else begin

		assign wt_expired = 1'b0;

	end


	// IRQ
	// ---

	always @(posedge clk)
		irq <= (
			(cfg_wt_ie & wt_expired) |
			(cfg_tx_irq_exc  & (tx_ef_parity | txf_overflow)) |
			(cfg_tx_irq_fifo & (txf_empty)) |
			(cfg_rx_irq_exc  & (rx_ef_parity | rx_ef_frame | rxf_overflow)) |
			(cfg_rx_irq_fifo & (~rxf_empty))
		);

endmodule // iso7816_wb
