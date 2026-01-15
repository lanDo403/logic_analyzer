`timescale 1ns / 1ps

module LVDS #(
	parameter LVDS_LEN = 8
)(
	input  [1:0] 	Clock_diff,
	input  [LVDS_LEN-1:0] 	Data_p,
	input  [LVDS_LEN-1:0] 	Data_n,
	input  [1:0] 	Strob_diff,	
	output [LVDS_LEN-1:0]   DataOUT,
   output 			StrobOUT,
	output 			ClockOUT
    );
	 
	//---------------------------------------------------------------------
	// Дополнительные сигналы
	//--------------------------------------------------------------------- 
	// Сигналы для пропуска через входные буфферы
	wire [LVDS_LEN-1:0] 	data_tx;	
	wire clock_out;
	wire strob_out;	
	
	reg [LVDS_LEN-1:0] 	data_rx;		// Данные после автомата считывающиеся по спадающему фронту
	reg strob_rx;
	
	//---------------------------------------------------------------------
	// Входные буферы
	//---------------------------------------------------------------------
	IBUFDS #(
		.IOSTANDARD("DEFAULT") // Specify the output I/O standard
	) IBUFDS_clock (
		.O(clock_out),     // Buffer output
		.IB(Clock_diff[1]),    // Diff_n buffer input (connect directly to top-level port)
		.I(Clock_diff[0])      // Diff_p buffer input (connect directly to top-level port) 
	);

	genvar i;
	generate
		for (i = 0; i < LVDS_LEN; i = i + 1) begin : lvds_bufs
			IBUFDS #(
				.IOSTANDARD("DEFAULT") // Specify the output I/O standard
			) IBUFDS_data (
				.O(data_tx[i]),     // Buffer output
				.IB(Data_n[i]),    // Diff_n buffer input (connect directly to top-level port)
				.I(Data_p[i])      // Diff_p buffer input (connect directly to top-level port) 
			);
		end
	endgenerate

	IBUFDS #(
		.IOSTANDARD("DEFAULT") // Specify the output I/O standard
	) IBUFDS_strob (
		.O(strob_out),     // Buffer output
		.IB(Strob_diff[1]),    // Diff_n buffer input (connect directly to top-level port)
		.I(Strob_diff[0])      // Diff_p buffer input (connect directly to top-level port) 
	);
	

	//---------------------------------------------------------------------
	// Считывание данных по спадающему фронту
	//---------------------------------------------------------------------
	always @(negedge clock_out) begin 
		data_rx <= data_tx;
		strob_rx <= strob_out;
	end
	
	assign DataOUT 	= data_rx;
	assign StrobOUT 	= strob_rx;
	assign ClockOUT	= clock_out;

endmodule
