`timescale 1ns / 1ps

module packer8to32 #(
	parameter DATA_LEN = 32,
	parameter LVDS_LEN = 8
)
(
	input 						clk,
	input 						rst_n,
	input 						valid_i,
	input  [LVDS_LEN-1:0] 	data_i,
	output 						valid_o, 	// Выходной сигнал для записи в FIFO
	output [DATA_LEN-1:0] 	data_o			// Данные в FIFO
    );

	reg [23:0] data_ff;
	reg [DATA_LEN-1:0] data_ff_o;
	reg [1:0] 	byte_counter;
	reg 			valid_byte;
	
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			byte_counter 	<= 2'd0;
			valid_byte 		<= 1'b0;
			data_ff 			<= 32'd0;
			data_ff_o 	<= 32'd0;
		end
		else begin
			valid_byte <= 1'b0;
			if (valid_i) begin
				case (byte_counter)
					2'd0:	data_ff[7:0] 	<= data_i;
					2'd1:	data_ff[15:8] 	<= data_i;
					2'd2:	data_ff[23:16] <= data_i;
					2'd3:	begin
						data_ff_o <= {data_i, data_ff};
						valid_byte <= 1'b1;
					end
				endcase
				byte_counter <= (byte_counter == 2'd3) ? 2'd0 : byte_counter + 1'b1;
			end
		end
	end
	
	assign valid_o = valid_byte;
	assign data_o 	= data_ff_o;
endmodule
