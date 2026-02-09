`timescale 1ns / 1ps

// ------------------------------------------------------------
// Заглушки входных буферов для симуляции (ISim).
// В синтезе используются примитивы Xilinx.
// ------------------------------------------------------------
module IBUFG #(parameter IOSTANDARD="LVCMOS33") (
   output wire O,
   input  wire I
);
   assign O = I;
endmodule

module IBUF #(parameter IOSTANDARD="LVCMOS33") (
   output wire O,
   input  wire I
);
   assign O = I;
endmodule


module lvds_tb;

   // Параметры теста
   localparam integer TOTAL_WORDS = 3402;
   localparam integer PAUSE_LEN   = 16;

   localparam integer LVDS_LEN = 8;
   localparam integer DATA_LEN = 32;
   localparam integer FIFO_DEPTH = 1024;
   localparam integer ADDR_LEN = $clog2(FIFO_DEPTH);

   localparam integer MAX_WORDS = (TOTAL_WORDS / 4) + 4;

   // Сигналы тестбенча
   reg tb_clock = 1'b0;
   reg tb_ft_clk = 1'b0;
   reg tb_strob = 1'b0;
   reg rst_n    = 1'b0;

   reg  [7:0] data_p;

   // Генераторы тактов
   always #10 tb_clock = ~tb_clock;
   always #5  tb_ft_clk = ~tb_ft_clk;

   // Данные из файла
   reg [7:0] byte_seq_p [0:TOTAL_WORDS-1];

   // Ожидаемые 32-битные слова (только при strobe=1)
   reg [31:0] exp_words [0:MAX_WORDS-1];
   integer    exp_words_n;
   integer    got_words_n;

   // =========================================================
   // DUT: LVDS -> packer8to32 -> fifo_dualport + sram_dp
   // =========================================================
   wire [7:0] DataOUT;
   wire       StrobOUT;
   wire       ClockOUT;

   LVDS #(
      .LVDS_LEN(LVDS_LEN)
   ) u_lvds (
      .clk_i(tb_clock),
      .strob_i(tb_strob),
      .data_i(data_p),
      .data_o(DataOUT),
      .strob_o(StrobOUT),
      .clk_o(ClockOUT)
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

   // FIFO + SRAM
   wire [DATA_LEN-1:0] fifo_data_o;
   wire [DATA_LEN-1:0] sram_in;
   wire [DATA_LEN-1:0] sram_out;
   wire                fifo_wen_o;
   wire                fifo_ren_n;
   wire [ADDR_LEN-1:0] fifo_addr_wr;
   wire [ADDR_LEN-1:0] fifo_addr_rd;
   wire                fifo_full;
   wire                fifo_empty;

   reg                 rd_en;
   reg                 rd_en_d;

   fifo_dualport #(
      .DATA_LEN(DATA_LEN),
      .DEPTH(FIFO_DEPTH)
   ) u_fifo (
      .clk_wr(ClockOUT),
      .clk_rd(tb_ft_clk),
      .rst_n(rst_n),
      .wen_i(pack_vld),
      .ren_i(rd_en),
      .sram_data_r(sram_out),
      .data_i(pack_data),
      .data_o(fifo_data_o),
      .sram_data_w(sram_in),
      .wen_o(fifo_wen_o),
      .ren_o(fifo_ren_n),
      .wr_addr_o(fifo_addr_wr),
      .rd_addr_o(fifo_addr_rd),
      .full(fifo_full),
      .empty(fifo_empty)
   );

   wire fifo_ren = ~fifo_ren_n;

   sram_dp #(
      .DATA_LEN(DATA_LEN),
      .DEPTH(FIFO_DEPTH)
   ) u_sram (
      .wr_clk(ClockOUT),
      .rd_clk(tb_ft_clk),
      .wen(fifo_wen_o),
      .ren(fifo_ren),
      .wr_addr(fifo_addr_wr),
      .rd_addr(fifo_addr_rd),
      .data_i(sram_in),
      .data_o(sram_out)
   );

   // =========================================================
   // TASK'И
   // =========================================================

   // Сброс сигналов и начальная инициализация
   task tb_reset;
      integer n;
      begin
         rst_n = 1'b0;
         tb_strob = 1'b0;
         data_p = 8'h00;
         for (n = 0; n < 4; n = n + 1)
            @(posedge tb_clock);
         rst_n = 1'b1;
         @(posedge tb_clock);
      end
   endtask

   // Загрузка входного потока из файла data_p
   task load_vectors;
      integer fd_p;
      integer i, r;
      begin
         fd_p = $fopen("data_p", "r");
         if (fd_p == 0) begin
            $display("ОШИБКА: не удалось открыть файл data_p");
            #1000;
            $finish;
         end

         for (i = 0; i < TOTAL_WORDS; i = i + 1) begin
            r = $fscanf(fd_p, "%h\n", byte_seq_p[i]);
         end

         $fclose(fd_p);
      end
   endtask

   // Проверка, начинается ли пауза в позиции idx (FF 00 00 00 x4)
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
               expected = 8'h00;
               if ((t % 4) == 0) expected = 8'hFF;
               if (byte_seq_p[idx + t] !== expected)
                  is_pause = 1'b0;
            end
         end
      end
   endtask

   // Формирование ожидаемых 32-битных слов (пропуск пауз)
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

   // Передача одного байта с управлением strobe
   task send_one_byte(input [7:0] bp, input strobe);
      begin
         @(negedge tb_clock);
         data_p <= bp;
         tb_strob <= strobe;
      end
   endtask

   // Передача всего потока с учетом пауз
   task send_all;
      integer idx;
      integer t;
      reg pause_here;
      begin
         idx = 0;
         while (idx < TOTAL_WORDS) begin
            is_pause_at(idx, pause_here);

            if (pause_here) begin
               for (t = 0; t < PAUSE_LEN; t = t + 1) begin
                  send_one_byte(byte_seq_p[idx], 1'b0);
                  idx = idx + 1;
               end
            end else begin
               send_one_byte(byte_seq_p[idx], 1'b1);
               idx = idx + 1;
            end
         end

         @(negedge tb_clock);
         tb_strob <= 1'b0;
      end
   endtask

   // Сравнение прочитанного из FIFO слова с эталоном
   task expect_fifo_word(input integer wi, input [31:0] got);
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

   // Ожидание заданного числа тактов в домене чтения
   task wait_ft_cycles(input integer cycles);
      integer k;
      begin
         for (k = 0; k < cycles; k = k + 1)
            @(posedge tb_ft_clk);
      end
   endtask

   // =========================================================
   // MAIN
   // =========================================================
   initial begin
      got_words_n = 0;

      load_vectors();
      build_expected_words();
      tb_reset();

      send_all();

      wait_ft_cycles(2000);

      $display("ТЕСТ ЗАВЕРШЕН. Ожидалось слов=%0d, Получено слов=%0d",
               exp_words_n, got_words_n);

      if (got_words_n !== exp_words_n) begin
         $display("ОШИБКА: количество слов не совпадает");
         $stop;
      end

      if (!fifo_empty) begin
         $display("ОШИБКА: FIFO не пуст после чтения");
         $stop;
      end

      $display("ТЕСТ ПРОЙДЕН УСПЕШНО");
      $stop;
   end


   // =========================================================
   // Монитор чтения FIFO в домене tb_ft_clk
   // =========================================================
   always @(posedge tb_ft_clk or negedge rst_n) begin
      if (!rst_n) begin
         rd_en <= 1'b0;
         rd_en_d <= 1'b0;
         got_words_n <= 0;
      end else begin
         rd_en <= ~fifo_empty;
         rd_en_d <= rd_en;
         if (rd_en_d) begin
            expect_fifo_word(got_words_n, fifo_data_o);
            got_words_n <= got_words_n + 1;
         end
      end
   end

   // Контроль переполнения FIFO при записи
   always @(posedge ClockOUT) begin
      if (rst_n && fifo_full && pack_vld) begin
         $display("ОШИБКА: FIFO переполнен во время записи");
         $stop;
      end
   end

endmodule
