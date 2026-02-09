`timescale 1ns / 1ps

module fifo_top #(
	parameter LVDS_LEN = 8,
	parameter DATA_LEN = 32,
	parameter BE_LEN = 4,
	parameter FIFO_DEPTH = 1024,
	parameter ADDR_LEN = $clog2(FIFO_DEPTH)
)(
	// LVDS signals from FPGA logic
	input   				LVDS_CLK,
	input  [LVDS_LEN-1:0] 	LVDS_DATA,
	input   				LVDS_STROB,	
	
    input 					CLK,		// Clock signal from FT601
    input 					RESET_N,	// Reset signal from FT601	
    input 					TXE_N,	// Trancieve empty signal from FT601
    input 					RXF_N,	//	Receive full signal from FT601
    output 					OE_N,		// Output enable signal to FT601
    output 					WR_N,		// Write enable signal to FT601
    output 					RD_N,		// Read enable signal to FT601
	inout [BE_LEN-1:0] 		BE,		// In and out byte enable bus connected to FT601
    inout [DATA_LEN-1:0] 	DATA		// In and out data bus connected to FT601
    );
	// Сигналы в подключениях к модулям с исключительно верхними регистрами - сигналы FT601,
	//	по этой логике легко увидеть, где конкретно эти сигналы подключаются
	 
	//-------------------------------------------------------------
	// Подключение к приёмнику LVDS
	//------------------------------------------------------------- 
	wire [LVDS_LEN-1:0] lvds_data; 	// От модуля приёмника LVDS в модуль упаковщик 8бит-32бита
	wire lvds_strob;	// LVDS строб (сигнал валидности)	
	wire lvds_clk;	// LVDS тактовая частота, которая будет использоваться для записи в FIFO

	LVDS lvds(
		.clk_i(LVDS_CLK),
		.strob_i(LVDS_STROB),
		.data_i(LVDS_DATA),
		.data_o(lvds_data),
		.strob_o(lvds_strob),
		.clk_o(lvds_clk)
	);
	
	//-------------------------------------------------------------
	// Подключение к упаковщику 8 в 32 бита
	//-------------------------------------------------------------
	// ***wire 						valid_in_packer;
	// ***wire [LVDS_LEN-1:0] 	din_packer;
	wire packer_valid_o;
	wire [DATA_LEN-1:0]	packer_data_o;

	packer8to32 packer(
		.clk(lvds_clk),
		.rst_n(RESET_N),
		.valid_i(lvds_strob),
		.data_i(lvds_data),
		.valid_o(packer_valid_o),
		.data_o(packer_data_o)
	);
	
	//-------------------------------------------------------------
	// Подключение к FIFO
	//-------------------------------------------------------------
	// ***wire [DATA_LEN-1:0]	fifo_data_i;
	// ***wire 						fifo_wr_en_fifo_i;
	wire [DATA_LEN-1:0]	fifo_data_o;
	wire 						full_fifo;
	wire 						empty_fifo;
	wire fifo_wen_o, fifo_ren_o;
	wire [ADDR_LEN-1:0] fifo_addr_wr, fifo_addr_rd;
	// ***wr_addr_fifo_out, rd_addr_fifo_out;
	
	wire [DATA_LEN-1:0] sram_in, sram_out; // Данные в/из SRAM
	
	wire fifo_pop_n;	// Сигнал, который определяет, когда необходимо вытаскивать данные из fifo_dualport в fifo_fsm
	
	// ***assign wr_en_fifo_in = valid_out_packer;
	// ***assign din_fifo = dout_packer;

	fifo_dualport #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) fifo(
		.clk_wr(lvds_clk),
		.clk_rd(CLK),
		.rst_n(RESET_N),
		.wen_i(packer_valid_o),
		.ren_i(fifo_pop_n), 
		.sram_data_r(sram_out),
		.data_i(packer_data_o),
		.data_o(fifo_data_o),
		.sram_data_w(sram_in),
		.wen_o(fifo_wen_o),
		.ren_o(fifo_ren_o),
		.wr_addr_o(fifo_addr_wr),
		.rd_addr_o(fifo_addr_rd),
		.full(full_fifo),
		.empty(empty_fifo)
	);
	
	
	//-------------------------------------------------------------
	// Подключение к SRAM
	//-------------------------------------------------------------
	// ***wire wr_en_sram, rd_en_sram_n;
	// ***wire [ADDR_LEN-1:0] wr_addr_sram, rd_addr_sram;
	
	// ***assign wr_en_sram = wr_en_fifo_out;
	// ***assign rd_en_sram_n = rd_en_fifo_out_n;	
	// ***assign wr_addr_sram = wr_addr_fifo_out;
	// ***assign rd_addr_sram = rd_addr_fifo_out;
	
	sram_dp #(
		.DATA_LEN(DATA_LEN),
		.DEPTH(FIFO_DEPTH)
	) mem(
		.wr_clk(lvds_clk),
		.rd_clk(CLK),
		.wen(fifo_wen_o),
		.ren(fifo_ren_o),
		.wr_addr(fifo_addr_wr),
		.rd_addr(fifo_addr_rd),
		.data_i(sram_in),
		.data_o(sram_out)
	);
	
	//-------------------------------------------------------------
	// Подключение к FSM 
	//-------------------------------------------------------------
	// tx означает "на ПЛИС от FT601"
	// rx means "от ПЛИС на FT601"
	// ***wire [DATA_LEN-1:0]  fsm_in;
	wire [DATA_LEN-1:0] 	rx_data;
	wire [DATA_LEN-1:0]	tx_data;
	wire [BE_LEN-1:0] 	rx_be;
	wire [BE_LEN-1:0] 	tx_be;
	wire oe_n;
	wire wr_n;
	wire rd_n;
	wire drive_tx; // Сигнал, определяющий момент времени для записи по шине DATA в FT601, дабы не было конфликтов записи и чтения на шине DATA
	
	// ***assign fsm_in = fifo_data_o;
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
		.fsm_data_i(fifo_data_o),
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
