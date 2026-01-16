`timescale 1ns / 1ps

// ------------------------------------------------------------
// Поведенческая заглушка IBUFDS для симуляции (ISim).
// В реальном синтезе используется примитив Xilinx.
// ------------------------------------------------------------
module IBUFDS #(parameter IOSTANDARD="DEFAULT") (
   output wire O,
   input  wire I,
   input  wire IB
);
   assign O = I;
endmodule


module lvds_tb;

   // Параметры теста
   localparam integer TOTAL_WORDS = 3402;   // всего байтов во входных файлах
   localparam integer PAUSE_LEN   = 16;     // длина паузы (FF FF ... FF)

   localparam integer LVDS_LEN = 8;
   localparam integer DATA_LEN = 32;

   // Сигналы тестбенча
   reg tb_clock = 1'b0;
   reg tb_strob = 1'b0;
   reg rst_n    = 1'b0;

   reg  [7:0] data_p;
   reg  [7:0] data_n;

   wire [1:0] clock_diff = {~tb_clock, tb_clock};
   wire [1:0] strob_diff = {~tb_strob, tb_strob};

   // Частота 50 МГц
   always #10 tb_clock = ~tb_clock;

   // Данные из файлов
   reg [7:0] byte_seq_p [0:TOTAL_WORDS-1];
   reg [7:0] byte_seq_n [0:TOTAL_WORDS-1];

   // Ожидаемые 32-битные слова (только при strobe=1)
   reg [31:0] exp_words [0:(TOTAL_WORDS/4)];
   integer    exp_words_n;
   integer    got_words_n;

   // DUT: LVDS -> packer8to32
   wire [7:0] DataOUT;
   wire       StrobOUT;
   wire       ClockOUT;

   LVDS #(
      .LVDS_LEN(LVDS_LEN)
   ) u_lvds (
      .Clock_diff(clock_diff),
      .Data_p(data_p),
      .Data_n(data_n),
      .Strob_diff(strob_diff),
      .DataOUT(DataOUT),
      .StrobOUT(StrobOUT),
      .ClockOUT(ClockOUT)
   );

   wire [DATA_LEN-1:0] pack_data;
   wire                pack_vld;

   packer8to32 #(
      .DATA_LEN(DATA_LEN),
      .LVDS_LEN(LVDS_LEN)
   ) u_packer (
      .clk(ClockOUT),
      .rst_n(rst_n),
      .valid_in(StrobOUT),
      .data_in(DataOUT),
      .valid_out(pack_vld),
      .data_out(pack_data)
   );

   // =========================================================
   // TASK'И
   // =========================================================

   // Сброс
   task tb_reset;
      integer n;
      begin
         rst_n = 1'b0;
         tb_strob = 1'b0;
         data_p = 8'h00;
         data_n = 8'hFF;
         for (n = 0; n < 4; n = n + 1)
            @(posedge tb_clock);
         rst_n = 1'b1;
         @(posedge tb_clock);
      end
   endtask


   // Загрузка данных из файлов data_p / data_n
   task load_vectors;
      integer fd_p, fd_n;
      integer i, r;
      begin
         fd_p = $fopen("data_p", "r");
         fd_n = $fopen("data_n", "r");
         if (fd_p == 0 || fd_n == 0) begin
            $display("ОШИБКА: не удалось открыть файлы data_p или data_n");
            #1000;
            $finish;
         end

         for (i = 0; i < TOTAL_WORDS; i = i + 1) begin
            r = $fscanf(fd_p, "%h\n", byte_seq_p[i]);
            r = $fscanf(fd_n, "%h\n", byte_seq_n[i]);
         end

         $fclose(fd_p);
         $fclose(fd_n);
      end
   endtask


   // Проверка: начинается ли в позиции idx пауза (PAUSE_LEN байтов FF)
      // ????????: ?????????? ?? ? ??????? idx ????? (FF 00 00 00 x4)
   task is_pause_at(
      input  integer idx,
      output reg     is_pause
   );
      integer t;
      reg [7:0] expected;
      begin
         is_pause = 1'b1;

         if (idx + PAUSE_LEN > TOTAL_WORDS)
            is_pause = 1'b0;
         else begin
            for (t = 0; t < PAUSE_LEN; t = t + 1) begin
               expected = ((t % 4) == 0) ? 8'hFF : 8'h00;
               if (byte_seq_p[idx + t] !== expected)
                  is_pause = 1'b0;
            end
         end
      end
   endtask


   // Формирование ожидаемых 32-битных слов (пропуская паузы)
   task build_expected_words;
      integer i;
      reg [31:0] w;
      reg [1:0]  cnt;
      reg pause_here;
      begin
         w = 32'd0;
         cnt = 2'd0;
         exp_words_n = 0;

         i = 0;
         while (i < TOTAL_WORDS) begin
            is_pause_at(i, pause_here);

            if (pause_here)
               i = i + PAUSE_LEN;
            else begin
               case (cnt)
                  2'd0: w[7:0]   = byte_seq_p[i];
                  2'd1: w[15:8]  = byte_seq_p[i];
                  2'd2: w[23:16] = byte_seq_p[i];
                  2'd3: begin
                     w[31:24] = byte_seq_p[i];
                     exp_words[exp_words_n] = w;
                     exp_words_n = exp_words_n + 1;
                  end
               endcase
               cnt = cnt + 1;
               i = i + 1;
            end
         end

         if (cnt != 2'd0)
            $display("ПРЕДУПРЕЖДЕНИЕ: количество валидных байтов не кратно 4");
      end
   endtask


   // Передача одного байта
   task send_one_byte(input [7:0] bp, input [7:0] bn, input strobe);
      begin
         @(posedge tb_clock);
         data_p <= bp;
         data_n <= bn;
			tb_strob <= strobe;
      end
   endtask


   // Передача всех данных с автоматическим управлением strobe
   task send_all;
      integer idx;
      integer t;
      reg pause_here;
      begin
         idx = 0;
         while (idx < TOTAL_WORDS) begin
            is_pause_at(idx, pause_here);

            if (pause_here) begin
               tb_strob = 1'b0;
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  send_one_byte(byte_seq_p[idx], byte_seq_n[idx], 1'b0);
                  idx = idx + 1;
               end
            end else begin
               send_one_byte(byte_seq_p[idx], byte_seq_n[idx], 1'b1);
               idx = idx + 1;
            end
         end

			@(posedge tb_clock)
         tb_strob = 1'b0;
      end
   endtask


   // Проверка слова, полученного из packer
   task expect_packer_word(input integer wi, input [31:0] got);
      begin
         if (wi >= exp_words_n) begin
            $display("ОШИБКА: получено лишнее слово [%0d] = %h", wi, got);
            $stop;
         end
         if (got !== exp_words[wi]) begin
            $display("ОШИБКА слова [%0d]: получено=%h ожидается=%h",
                     wi, got, exp_words[wi]);
            $stop;
         end
      end
   endtask


   // Ожидание N тактов
   task wait_cycles(input integer cycles);
      integer k;
      begin
         for (k = 0; k < cycles; k = k + 1)
            @(posedge tb_clock);
      end
   endtask

   // =========================================================
   // MAIN
   // =========================================================
   initial begin
      got_words_n = 0;

      load_vectors();
		$display("Первые байты из файлов: data_p[0]=%h data_n[0]=%h", byte_seq_p[0], byte_seq_n[0]);
      build_expected_words();
      tb_reset();

      send_all();

      // Дать данным дойти по пайплайну
      wait_cycles(64);

      $display("ТЕСТ ЗАВЕРШЁН. Ожидалось слов=%0d, Получено слов=%0d",
               exp_words_n, got_words_n);

      if (got_words_n !== exp_words_n) begin
         $display("ОШИБКА: количество слов не совпадает");
         $stop;
      end

      $display("ТЕСТ ПРОЙДЕН УСПЕШНО");
      $stop;
   end


   // =========================================================
   // Монитор выхода packer
   // =========================================================
   always @(posedge ClockOUT) begin
      if (!rst_n)
         got_words_n <= 0;
      else if (pack_vld) begin
         expect_packer_word(got_words_n, pack_data);
         got_words_n <= got_words_n + 1;
      end
   end

endmodule
