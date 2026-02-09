`timescale 1ns / 1ps

module LVDS #(
	parameter LVDS_LEN = 8
)(
	input clk_i,
	input strob_i,	
	input [LVDS_LEN-1:0] data_i,
	
	output [LVDS_LEN-1:0] data_o,
    output strob_o,
	output clk_o
    );
	 
	//---------------------------------------------------------------------
	// Дополнительные сигналы
	//--------------------------------------------------------------------- 
	// Сигналы для пропуска через входные буфферы
	wire [LVDS_LEN-1:0] data_buf;
	wire strob_buf;	
	wire clk_buf;

	// Выходы с регистров
	reg [LVDS_LEN-1:0] data_rx;
	reg strob_rx;
	
	//---------------------------------------------------------------------
	// Входные буферы
	//---------------------------------------------------------------------
	IBUFG #(
		.IOSTANDARD("LVCMOS33") // Specify the output I/O standard
	) IBUFG_clk (
		.O(clk_buf),     // Buffer output
		.I(clk_i)      // Diff_p buffer input (connect directly to top-level port) 
	);

	genvar i;
	generate
		for (i = 0; i < LVDS_LEN; i = i + 1) begin : data_bufs
			IBUF #(
				.IOSTANDARD("LVCMOS33") // Specify the output I/O standard
			) IBUF_data (
				.O(data_buf[i]),     // Buffer output
				.I(data_i[i])      // Diff_p buffer input (connect directly to top-level port) 
			);
		end
	endgenerate

	IBUF #(
		.IOSTANDARD("LVCMOS33") // Specify the output I/O standard
	) IBUF_strob (
		.O(strob_buf),     // Buffer output
		.I(strob_i)      // Diff_p buffer input (connect directly to top-level port) 
	);
	

	//---------------------------------------------------------------------
	// Смена данных по восходящему фронту, считывание данных по спадающему фронту
	//---------------------------------------------------------------------
	always @(posedge clk_buf) begin 
		data_rx <= data_buf;
		strob_rx <= strob_buf;
	end
	
	assign data_o 	= data_rx;
	assign strob_o = strob_rx;
	assign clk_o = clk_buf;

endmodule
