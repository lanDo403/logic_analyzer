`timescale 1ns / 1ps

module fifo_dualport#(
	parameter DATA_LEN = 32,
	parameter DEPTH = 1024,
	parameter ADDR_LEN = $clog2(DEPTH)
)(
	input 						clk_wr,
	input							clk_rd,
	input 						rst_n,			
	input 						wr_en_in, // Разрешение на запись в память после упаковщика	
	input 						rd_en_in_n,  // Разрешение на чтение из FT601
	input [DATA_LEN-1:0] 	sram_data_r, // Данные, которые читаются из памяти
	input [DATA_LEN-1:0] 	data_in,	// Данные, поступившие извне, которые еще не в памяти, но должны записаться туда
	output [DATA_LEN-1:0]  	data_out, // Данные, которые попадут в FSM -> FT601
	output [DATA_LEN-1:0]	sram_data_w, // Данные, которые записываются в память
	output 						wr_en_out, // Разрешение на запись в память
	output 						rd_en_out_n, // Разрешение на чтение в память
	output [ADDR_LEN-1:0]	wr_addr_out,
	output [ADDR_LEN-1:0]	rd_addr_out,
	output 						full,			
	output 						empty		
    ); 
	 
	reg [DATA_LEN-1:0] wr_data;
	//reg [DATA_LEN-1:0] rd_data;
	
	reg [ADDR_LEN:0] wr_ptr_bin, wr_ptr_bin_next;
	reg [ADDR_LEN:0] rd_ptr_bin, rd_ptr_bin_next;
	reg [ADDR_LEN:0] wr_ptr_gray, wr_ptr_gray_next;
	reg [ADDR_LEN:0] rd_ptr_gray, rd_ptr_gray_next;
	
	reg [ADDR_LEN:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
	reg [ADDR_LEN:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
	
	//-------------------------------------------------------------
	// Указатели на запись(адрес и грея)
	//-------------------------------------------------------------
	always @(negedge clk_wr or negedge rst_n) begin
		if (!rst_n) begin
			wr_ptr_bin <= 0;
			wr_ptr_gray <= 0;
		end
		else begin
			wr_ptr_bin <= wr_ptr_bin_next;
			wr_ptr_gray <= wr_ptr_gray_next;
			if (wr_en_in && !full)
				wr_data <= data_in;
		end
	end
	
	always @(*) begin
		wr_ptr_bin_next = wr_ptr_bin + (wr_en_in & !full);
		wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
	end
	
	//-------------------------------------------------------------
	// Указатели на чтение(адрес и грея)
	//-------------------------------------------------------------
	always @(negedge clk_rd or negedge rst_n) begin
		if (!rst_n) begin
			rd_ptr_bin <= 0;
			rd_ptr_gray <= 0;
		end
		else begin
			rd_ptr_bin <= rd_ptr_bin_next;
			rd_ptr_gray <= rd_ptr_gray_next;
			/*
			if (!rd_en_in_n && !empty)
				rd_data <= sram_data_r;
			*/
		end
	end
	
	always @(*) begin
		rd_ptr_bin_next = rd_ptr_bin + (!rd_en_in_n & !empty);
		rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;
	end
	
	//-------------------------------------------------------------
	// Синхронизация указателей грея
	//-------------------------------------------------------------
	always @(negedge clk_wr or negedge rst_n) begin
		if (!rst_n) begin
			rd_ptr_gray_sync1 <= 0;
			rd_ptr_gray_sync2 <= 0;
		end
		else begin
			rd_ptr_gray_sync1 <= rd_ptr_gray;
			rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
		end
	end
	
	always @(negedge clk_rd or negedge rst_n) begin
		if (!rst_n) begin
			wr_ptr_gray_sync1 <= 0;
			wr_ptr_gray_sync2 <= 0;
		end
		else begin
			wr_ptr_gray_sync1 <= wr_ptr_gray;
			wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
		end
	end
	
	//-------------------------------------------------------------
	// Логика выходных сигналов
	//-------------------------------------------------------------
	assign empty 	= (rd_ptr_gray == wr_ptr_gray_sync2);
	assign full 	= (wr_ptr_gray_next == {~rd_ptr_gray_sync2[ADDR_LEN:ADDR_LEN-1], rd_ptr_gray_sync2[ADDR_LEN-2:0]});
	
	assign wr_en_out = wr_en_in & ~full;
	assign rd_en_out_n = ~(~rd_en_in_n & ~empty);
	assign wr_addr_out = wr_ptr_bin[ADDR_LEN-1:0];
	assign rd_addr_out = rd_ptr_bin[ADDR_LEN-1:0];
	assign sram_data_w = wr_data;
	// assign data_out = rd_data;
	assign data_out = sram_data_r;

endmodule
