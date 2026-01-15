`timescale 1ns / 1ps

module fifo_top #(
	parameter LVDS_LEN = 8,
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_DEPTH = 1024,
	parameter ADDR_LEN = $clog2(FIFO_DEPTH)
)(
	// LVDS signals from FPGA logic
	input  [1:0] 				Clock_diff,
	input  [LVDS_LEN-1:0] 	Data_p,
	input  [LVDS_LEN-1:0] 	Data_n,
	input  [1:0] 				Strob_diff,	
   input 						CLK,		// Clock signal from FT601
   input 						RESET_N,	// Reset signal from FT601	
   input 						TXE_N,	// Trancieve empty signal from FT601
   input 						RXF_N,	//	Receive full signal from FT601
   output 						OE_N,		// Output enable signal to FT601
   output 						WR_N,		// Write enable signal to FT601
   output 						RD_N,		// Read enable signal to FT601
	inout [BE_LEN-1:0] 		BE,		// In and out byte enable bus connected to FT601
   inout [DATA_LEN-1:0] 	DATA		// In and out data bus connected to FT601
    );
	// Сигналы в подключениях к модулям с исключительно верхними регистрами - сигналы FT601,
	//	по этой логике легко увидеть, где конкретно эти сигналы подключаются
	 
	//-------------------------------------------------------------
	// Подключение к приёмнику LVDS
	//------------------------------------------------------------- 
	wire [LVDS_LEN-1:0] 	dout_lvds; 	// От модуля приёмника LVDS в модуль упаковщик 8бит-32бита
	wire 						valid_lvds;		// LVDS строб (сигнал валидности)	
	wire 						wr_clk;			// LVDS тактовая частота, которая будет использоваться для записи в FIFO

	LVDS lvds(
		.Clock_diff(Clock_diff),
		.Data_p(Data_p),
		.Data_n(Data_n),
		.Strob_diff(Strob_diff),
		.DataOUT(dout_lvds),
		.StrobOUT(valid_lvds),
		.ClockOUT(wr_clk)
	);
	
	//-------------------------------------------------------------
	// Подключение к упаковщику 8 в 32 бита
	//-------------------------------------------------------------
	wire 						valid_in_packer;
	wire [LVDS_LEN-1:0] 	din_packer;
	wire 						valid_out_packer;
	wire [DATA_LEN-1:0]	dout_packer;
	
	assign valid_in_packer = valid_lvds;
	assign din_packer = dout_lvds;

	packer8to32 packer(
		.clk(wr_clk),
		.rst_n(RESET_N),
		.valid_in(valid_in_packer),
		.data_in(din_packer),
		.valid_out(valid_out_packer),
		.data_out(dout_packer)
	);
	
	//-------------------------------------------------------------
	// Подключение к FIFO
	//-------------------------------------------------------------
	wire [DATA_LEN-1:0]	din_fifo;
	wire 						wr_en_fifo_in;
	wire [DATA_LEN-1:0]	dout_fifo;
	wire 						full_fifo;
	wire 						empty_fifo;
	wire wr_en_fifo_out, rd_en_fifo_out_n;
	wire [ADDR_LEN-1:0] wr_addr_fifo_out, rd_addr_fifo_out;
	// Данные в/из SRAM
	wire [DATA_LEN-1:0] sram_in, sram_out;
	wire fifo_pop_n;	// Сигнал, который определяет, когда необходимо вытаскивать данные из fifo_dualport в fifo_fsm
	
	assign wr_en_fifo_in = valid_out_packer;
	assign din_fifo = dout_packer;

	fifo_dualport #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) fifo(
		.clk_wr(wr_clk),
		.clk_rd(CLK),
		.rst_n(RESET_N),
		.wr_en_in(wr_en_fifo_in),
		.rd_en_in_n(fifo_pop_n), 
		.sram_data_r(sram_out),
		.data_in(din_fifo),
		.data_out(dout_fifo),
		.sram_data_w(sram_in),
		.wr_en_out(wr_en_fifo_out),
		.rd_en_out_n(rd_en_fifo_out_n),
		.wr_addr_out(wr_addr_fifo_out),
		.rd_addr_out(rd_addr_fifo_out),
		.full(full_fifo),
		.empty(empty_fifo)
	);
	
	
	//-------------------------------------------------------------
	// Подключение к SRAM
	//-------------------------------------------------------------
	wire wr_en_sram, rd_en_sram_n;
	wire [ADDR_LEN-1:0] wr_addr_sram, rd_addr_sram;
	
	assign wr_en_sram = wr_en_fifo_out;
	assign rd_en_sram_n = rd_en_fifo_out_n;	
	assign wr_addr_sram = wr_addr_fifo_out;
	assign rd_addr_sram = rd_addr_fifo_out;
	
	sram_dp #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) i_mem (
		.wr_clk(wr_clk),
		.rd_clk(CLK),
		.wr_en(wr_en_sram),
		.rd_en_n(rd_en_sram_n),
		.wr_addr(wr_addr_sram),
		.rd_addr(rd_addr_sram),
		.data_i(sram_in),
		.data_o(sram_out)
	);
	
	//-------------------------------------------------------------
	// Подключение к FSM 
	//-------------------------------------------------------------
	// tx означает "на ПЛИС от FT601"
	// rx means "от ПЛИС на FT601"
	wire [DATA_LEN-1:0]  fsm_in;
	wire [DATA_LEN-1:0] 	rx_data;
	wire [DATA_LEN-1:0]	tx_data;
	wire [BE_LEN-1:0] 	rx_be;
	wire [BE_LEN-1:0] 	tx_be;
	wire oe_n;
	wire wr_n;
	wire rd_n;
	wire drive_tx; // Сигнал, определяющий момент времени для записи по шине DATA в FT601, дабы не было конфликтов записи и чтения на шине DATA
	
	assign fsm_in = dout_fifo;
	assign DATA 	= drive_tx ? tx_data : 32'hzzzzzzzz; // Отправка данных на FT601 по общей шине записи/чтения данных 
	assign rx_data = DATA; // Чтение данных с FT601
	assign BE 		= drive_tx ? tx_be : 4'hz; // Отправка BE на FT601 по общей шине записи/чтения BE
	assign rx_be 	= BE; // Чтение BE с FT601
	assign OE_N = oe_n;
	assign WR_N = wr_n;
	assign RD_N = rd_n;
	
	fifo_fsm fsm(
		.rst_n(RESET_N),
		.clk(CLK),
		.txe_n(TXE_N),
		.rxf_n(RXF_N),
		.fsm_data_in(fsm_in),
		.rx_data(rx_data),
		.be_i(rx_be),
		.full_fifo(full_fifo),
		.empty_fifo(empty_fifo),
		.tx_data(tx_data),
		.be_o(tx_be),
		.wr_n(wr_n),
		.rd_n(rd_n),
		.oe_n(oe_n),
		.drive_tx(drive_tx),
		.fifo_pop_n(fifo_pop_n)
	);
endmodule
