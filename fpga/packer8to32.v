`timescale 1ns / 1ps

module packer8to32 #(
	parameter DATA_LEN = 32,
	parameter LVDS_LEN = 8
)
(
	input 						clk,
	input 						rst_n,
	input 						valid_in,
	input  [LVDS_LEN-1:0] 		data_in,
	output 						valid_out, 	// Выходной сигнал для записи в FIFO
	output [DATA_LEN-1:0] 		data_out			// Данные в FIFO
    );

	reg [23:0] 			data_ff;
	reg [DATA_LEN-1:0] 	data_ff_out;

	reg [1:0] 	byte_counter;
	reg 		valid_byte;
	
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			byte_counter 	<= 2'd0;
			valid_byte 		<= 1'b0;
			data_ff 		<= 32'd0;
			data_ff_out 	<= 32'd0;
		end
		else begin
			valid_byte <= 1'b0;
			if (valid_in) begin
				case (byte_counter)
					2'd0:	data_ff[7:0] 	<= data_in;
					2'd1:	data_ff[15:8] 	<= data_in;
					2'd2:	data_ff[23:16] <= data_in;
					2'd3:	begin
						data_ff_out <= {data_in, data_ff};
						valid_byte  <= 1'b1;
					end
				endcase
				byte_counter <= (byte_counter == 2'd3) ? 2'd0 : byte_counter + 1'b1;
			end
		end
	end
	
	assign valid_out 	= valid_byte;
	assign data_out 	= data_ff_out;
endmodule
