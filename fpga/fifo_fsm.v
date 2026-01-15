`timescale 1ns / 1ps

module fifo_fsm
#(
	parameter DATA_LEN = 32,
	parameter BE_LEN   = 4
)
(
	//TODO: флаг be от фифо
	input  						rst_n,
	input  						clk,
	// Флаги с FT601
	input  						txe_n,		// Trancieve empty поступает с FT601 
	input  						rxf_n,		// Recieve full поступает с FT601
	input  [DATA_LEN-1:0]   fsm_data_in,	// Фифо плис лвдс
	input  [DATA_LEN-1:0]   rx_data,		// Данные, поступающие с FT601
	input  [BE_LEN-1:0] 		be_i,			// Byte enable, поступающий с FT601
	input 						full_fifo,
	input 						empty_fifo,
	
	output [DATA_LEN-1:0]  	tx_data,		// Данные, отправляющиеся на FT601
	output [BE_LEN-1:0]   	be_o,			// Byte enable, отправляющийся на FT601
	output  						wr_n,    
	output   					rd_n,
	output   					oe_n,
	output 						drive_tx,
	output 						fifo_pop_n
    );
	 
	// Параметры
	localparam IDLE   = 3'd0;
	localparam MODE   = 3'd1;
	localparam W_POP 	= 3'd2;
	localparam W_PREP = 3'd3;  // выставить DATA/BE
	localparam W_STB  = 3'd4;  // WR# импульс 1 такт
	localparam R_OE   = 3'd5;  // OE#=0, подождать 1 такт
	localparam R_STB  = 3'd6;  // RD# импульс 1 такт
	localparam R_CAP  = 3'd7;  // захват данных
	
	// Состояния
	reg [2:0] next_state;
	reg [2:0] state;
	
	// Дополнительные сигналы
	reg [DATA_LEN-1:0] 	tx_data_ff, rx_data_ff;
	reg [BE_LEN-1:0] 		be_ff;
	reg 						wr_ff, rd_ff, oe_ff;
	reg 						drive_tx_ff;
	reg 						fifo_pop_n_ff;
	
	// Управляющие сигнал с ПО на ПК, цепочка такая: ПК -> FT601 -> ПЛИС
	reg run_en;

	//-------------------------------------------------------------
	// state логика
	//-------------------------------------------------------------
	always @(negedge clk or negedge rst_n) begin
		if (!rst_n)
			state <= IDLE;
		else 
			state <= next_state;
	end
	
	//-------------------------------------------------------------
	// next_state логика
	//-------------------------------------------------------------	
	always @(*) begin
		next_state = state;
		case (state)
			IDLE: begin
				if (run_en) next_state = MODE;
				else        next_state = IDLE;
			end
			MODE: begin
				if (!run_en) 							next_state = IDLE;
				else if (!rxf_n)						next_state = R_OE;
				else if (!txe_n && !empty_fifo)	next_state = W_POP;
				else										next_state = MODE;
			end
			W_POP: begin
				if (!run_en)         next_state = IDLE;
				else if (txe_n)      next_state = MODE;
				else if (empty_fifo)	next_state = MODE;
				else                 next_state = W_PREP;
			end
			W_PREP: begin
				if (!run_en)         next_state = IDLE;
				else if (txe_n)      next_state = MODE;     // место кончилось
				else if (empty_fifo)	next_state = MODE;     // данных нет
				else                 next_state = W_STB;
			end
			W_STB: begin
				if (!run_en)               		next_state = IDLE;
				else if (!txe_n && !empty_fifo)	next_state = W_POP;
				else                       		next_state = MODE;
			end
			R_OE: begin
				if (!run_en)		next_state = IDLE;
				else if (rxf_n)	next_state = MODE;  // уже нечего читать
				else					next_state = R_STB;
			end
			R_STB: begin
				if (!run_en)		next_state = IDLE;
				else					next_state = R_CAP;
			end
			R_CAP: begin
				if (!run_en)      next_state = IDLE;
				else if (!rxf_n)	next_state = R_OE;   // можно читать следующую команду
				else              next_state = MODE;
			end
			default: next_state = IDLE;
		endcase
	end
	
	
	//-------------------------------------------------------------
	// Логика регистров
	//-------------------------------------------------------------
	always @(negedge clk or negedge rst_n) begin
		if (!rst_n) begin
			rd_ff 			<= 1'b1;
			wr_ff 			<= 1'b1;
			oe_ff 			<= 1'b1;
			drive_tx_ff 	<= 1'b0;
			fifo_pop_n_ff 	<= 1'b1;
			tx_data_ff 		<= 32'hzzzzzzzz;
			rx_data_ff  	<= 32'hzzzzzzzz;
			be_ff 			<= 4'hz;
		end
		else begin
			wr_ff        	<= 1'b1;
			rd_ff        	<= 1'b1;
			oe_ff        	<= 1'b1;
			drive_tx_ff  	<= 1'b0;
			fifo_pop_n_ff 	<= 1'b1;
			case (state)
			   IDLE, MODE: begin
					// ждем
			   end
			   W_POP: begin
					fifo_pop_n_ff <= 1'b0;  // 1-cycle pop
				   // шину пока не драйвим и не стробим
				   oe_ff       <= 1'b1;
				   drive_tx_ff <= 1'b0;
			   end
			   W_PREP: begin
					oe_ff       <= 1'b1;
					drive_tx_ff <= 1'b1;
					if (!txe_n && !empty_fifo && run_en) begin
						tx_data_ff <= fsm_data_in;
						be_ff      <= {BE_LEN{1'b1}}; // 4'hF
					end
			   end
			   W_STB: begin
					oe_ff       <= 1'b1;
				   drive_tx_ff <= 1'b1;
				   wr_ff       <= 1'b0;
			   end
			   R_OE: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
			   end
				R_STB: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
					rd_ff       <= 1'b0;  // 1-cycle RD# strobe
				end
				R_CAP: begin
					drive_tx_ff <= 1'b0;
					oe_ff       <= 1'b0;
					if (!rxf_n && !full_fifo && run_en)
						rx_data_ff <= rx_data;
				end
			endcase
		end
	end
	
	always @(negedge clk or negedge rst_n) begin
		if (!rst_n)
			run_en <= 1'b0; 
		else begin
			// обновляем run_en только когда мы реально захватили новое слово команды
			if (state == R_CAP) begin
				if (rx_data_ff == 32'h11111111) run_en <= 1'b1;  // START
				else if (rx_data_ff == 32'h00000000) run_en <= 1'b0;  // STOP
			end
		end
  end
	
	assign tx_data = tx_data_ff;
	assign be_o = be_ff;
	assign wr_n = wr_ff;
	assign rd_n = rd_ff;
	assign oe_n = oe_ff;
	assign drive_tx = drive_tx_ff;	
	assign fifo_pop_n = fifo_pop_n_ff;
	//?TODO: обработка информации с FT601(но по идее она не нужна, так как нет каких либо данных, поступающих с FT601)
		
endmodule
