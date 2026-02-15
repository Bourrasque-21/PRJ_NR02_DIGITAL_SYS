`timescale 1ns / 1ps

module top_stopwatch_watch (
    input wire clk,
    input wire reset,

    input wire [4:0] mode_sw,
    input wire       btn_8,
    input wire       btn_5,
    input wire       btn_2,
    input wire       sr04_start,

    input  wire echo,
    output wire trig,

    input  wire uart_rx,
    output wire uart_tx,

    output wire [3:0] fnd_digit,
    output wire [7:0] fnd_data,

    output wire [3:0] out_led,
    output wire       pc_mode_led
);

    wire [25:0] w_stopwatch_time;
    wire [23:0] w_clock_time;
    wire [12:0] w_distance;

    wire w_mode;

    wire i_btn_8;
    wire i_btn_5;
    wire i_btn_2;
    wire w_sr04_btn;

    wire clock_mode;
    wire time_set_mode;
    wire clk_next, clk_up, clk_down;

    wire       or_btn_r;
    wire       or_btn_n;
    wire       or_btn_c;

    wire       pc_ctrl_mode;
    wire [4:0] pc_mode_sw;

    wire       i_run_stop;
    wire       i_clear;
    wire       cu_btn_5;
    wire [4:0] mode_sw_com;

    wire [1:0] w_led_sel = {mode_sw_com[4], mode_sw_com[1]};
    wire [1:0] w_sys_mod = {mode_sw_com[4], mode_sw_com[1]};
    wire [3:0] w_clk_sel_led;

    wire [3:0] w_dist_c0 = (w_distance) % 10;
    wire [3:0] w_dist_c1 = (w_distance / 10) % 10;
    wire [3:0] w_dist_c2 = (w_distance / 100) % 10;
    wire [3:0] w_dist_c3 = w_distance / 1000;

    wire [25:0] w_dist_num = {10'd10, w_dist_c3, w_dist_c2, w_dist_c1, w_dist_c0};
    wire [25:0] w_sr04_label = {10'd0, 4'd10, 4'd11, 4'd0, 4'd4};
    wire [25:0] fnd_data_dist = (mode_sw_com[2] ? w_sr04_label : w_dist_num);

    wire       w_sr04_out, w_sw_clk_out0, w_sw_clk_out1, w_sw_clk_out2;
    wire       w_mode_swclk = (w_sys_mod == 2'b00) || (w_sys_mod == 2'b01);
    wire       w_mode_sr04  = (w_sys_mod == 2'b10);
    wire       w_mode_dht11 = (w_sys_mod == 2'b11);

    assign w_sr04_btn = w_mode_sr04 & w_sr04_out;

    assign w_sw_clk_out0 = (or_btn_r | i_btn_8) & w_mode_swclk;
    assign w_sw_clk_out1 = (or_btn_c | i_btn_2) & w_mode_swclk;
    assign w_sw_clk_out2 = (or_btn_n | i_btn_5) & w_mode_swclk;

    assign i_run_stop = w_sw_clk_out0;
    assign i_clear    = w_sw_clk_out1;
    assign cu_btn_5   = w_sw_clk_out2;

    assign mode_sw_com = pc_ctrl_mode ? pc_mode_sw : mode_sw;
    assign pc_mode_led = pc_ctrl_mode;

    assign out_led = (w_led_sel == 2'b11) ? 4'b0011 :
        (w_led_sel == 2'b10) ? 4'b0010 :
        (w_led_sel == 2'b01) ? (time_set_mode ? w_clk_sel_led : 4'b0001)
        : 4'b0000;

    sr04_ctrl_top U_SR04_CTRL (
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .sr04_start(w_sr04_btn),
        .trig(trig),
        .distance(w_distance)
    );

    btn_debounce U_SR04_BTN (
        .clk  (clk),
        .reset(reset),
        .i_btn(sr04_start),
        .o_btn(w_sr04_out)
    );

    uart_top U_UART (
        .clk    (clk),
        .reset  (reset),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),

        .o_btn_r(or_btn_r),
        .o_btn_n(or_btn_n),
        .o_btn_c(or_btn_c),

        .pc_ctrl_mode(pc_ctrl_mode),
        .pc_mode_sw  (pc_mode_sw),

        .clock_time24(w_clock_time)
    );

    clk_datapath U_CLOCK_DATAPATH (
        .clk  (clk),
        .reset(reset),

        .sw_time_set(time_set_mode),
        .btn_next   (clk_next),
        .up_count   (clk_up),
        .down_count (clk_down),
        .clock_mode (clock_mode),

        .c_msec(w_clock_time[6:0]),
        .c_sec (w_clock_time[12:7]),
        .c_min (w_clock_time[18:13]),
        .c_hour(w_clock_time[23:19]),

        .led(w_clk_sel_led)
    );

    btn_debounce U_BTN_8 (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_8),
        .o_btn(i_btn_8)
    );

    btn_debounce U_BTN_2 (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_2),
        .o_btn(i_btn_2)
    );

    btn_debounce U_BTN_5 (
        .clk  (clk),
        .reset(reset),
        .i_btn(btn_5),
        .o_btn(i_btn_5)
    );

    wire o_btn_8;
    wire o_btn_2;

    control_unit U_CONTROL_UNIT (
        .clk    (clk),
        .reset  (reset),
        .mode_sw({mode_sw_com[3], mode_sw_com[1], mode_sw_com[0]}),

        .i_run_stop(i_run_stop),
        .i_clear   (i_clear),
        .cu_btn_5  (cu_btn_5),

        .o_mode_sw (w_mode),
        .o_run_stop(o_btn_8),
        .o_clear   (o_btn_2),

        .clock_mode   (clock_mode),
        .time_set_mode(time_set_mode),
        .clk_next     (clk_next),
        .clk_up       (clk_up),
        .clk_down     (clk_down)
    );

    stopwatch_datapath U_STOPWATCH_DATAPATH (
        .clk     (clk),
        .reset   (reset),
        .mode_sw (w_mode),
        .clear   (o_btn_2),
        .run_stop(o_btn_8),

        .msec(w_stopwatch_time[6:0]),
        .sec (w_stopwatch_time[12:7]),
        .min (w_stopwatch_time[18:13]),
        .hour(w_stopwatch_time[25:19])
    );

    fnd_contr U_FND_CTRL (
        .clk          (clk),
        .reset        (reset),
        .sel_display  (mode_sw_com[2]),
        .sel_display_2({mode_sw_com[4], mode_sw_com[1]}),
        .fnd_in_data  (w_stopwatch_time),
        .fnd_in_data_2(w_clock_time),
        .fnd_dist_data(fnd_data_dist),
        .fnd_dht_data (26'd0),
        .fnd_digit    (fnd_digit),
        .fnd_data     (fnd_data)
    );

endmodule

module stopwatch_datapath (
    input wire clk,
    input wire reset,
    input wire mode_sw,
    input wire clear,
    input wire run_stop,

    output wire [6:0] msec,
    output wire [5:0] sec,
    output wire [5:0] min,
    output wire [6:0] hour
);

    wire w_tick_100hz;
    wire w_sec_tick, w_min_tick, w_hour_tick;

    tick_gen_100hz U_tick_gen (
        .clk         (clk),
        .reset       (reset),
        .i_run_stop  (run_stop),
        .o_tick_100hz(w_tick_100hz)
    );

    tick_counter #(
        .BIT_WIDTH(7),
        .TIMES(100)
    ) hour_counter (
        .clk     (clk),
        .reset   (reset),
        .i_tick  (w_hour_tick),
        .mode    (mode_sw),
        .clear   (clear),
        .run_stop(run_stop),
        .o_count (hour),
        .o_tick  ()
    );

    tick_counter #(
        .BIT_WIDTH(6),
        .TIMES(60)
    ) min_counter (
        .clk     (clk),
        .reset   (reset),
        .i_tick  (w_min_tick),
        .mode    (mode_sw),
        .clear   (clear),
        .run_stop(run_stop),
        .o_count (min),
        .o_tick  (w_hour_tick)
    );

    tick_counter #(
        .BIT_WIDTH(6),
        .TIMES(60)
    ) sec_counter (
        .clk     (clk),
        .reset   (reset),
        .i_tick  (w_sec_tick),
        .mode    (mode_sw),
        .clear   (clear),
        .run_stop(run_stop),
        .o_count (sec),
        .o_tick  (w_min_tick)
    );

    tick_counter #(
        .BIT_WIDTH(7),
        .TIMES(100)
    ) msec_counter (
        .clk     (clk),
        .reset   (reset),
        .i_tick  (w_tick_100hz),
        .mode    (mode_sw),
        .clear   (clear),
        .run_stop(run_stop),
        .o_count (msec),
        .o_tick  (w_sec_tick)
    );

endmodule

module tick_counter #(
    parameter BIT_WIDTH = 7,
    parameter TIMES     = 100
) (
    input wire clk,
    input wire reset,
    input wire i_tick,
    input wire mode,
    input wire clear,
    input wire run_stop,

    output wire [BIT_WIDTH-1:0] o_count,
    output reg                  o_tick
);
    reg [BIT_WIDTH-1:0] counter_reg, counter_next;

    assign o_count = counter_reg;

    always @(posedge clk or posedge reset) begin
        if (reset | clear) begin
            counter_reg <= 0;
        end else begin
            counter_reg <= counter_next;
        end
    end

    always @(*) begin
        counter_next = counter_reg;
        o_tick       = 1'b0;

        if (i_tick & run_stop) begin

            if (mode) begin
                if (counter_reg == 0) begin
                    counter_next = TIMES - 1;
                    o_tick       = 1'b1;
                end else begin
                    counter_next = counter_reg - 1'b1;
                end
            end
            else begin
                if (counter_reg == (TIMES - 1)) begin
                    counter_next = 0;
                    o_tick       = 1'b1;
                end else begin
                    counter_next = counter_reg + 1'b1;
                end
            end
        end
    end

endmodule

module tick_gen_100hz (
    input  wire clk,
    input  wire reset,
    input  wire i_run_stop,
    output reg  o_tick_100hz
);
    parameter F_COUNT = 100_000_000 / 100;
    reg [$clog2(F_COUNT)-1:0] r_counter;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_counter <= 0;
            o_tick_100hz <= 1'b0;
        end else begin
            if (i_run_stop) begin
                r_counter <= r_counter + 1'b1;
                if (r_counter == (F_COUNT - 1)) begin
                    r_counter <= 0;
                    o_tick_100hz <= 1'b1;
                end else begin
                    o_tick_100hz <= 1'b0;
                end
            end else begin
                o_tick_100hz <= 1'b0;
            end
        end
    end
endmodule

module clk_datapath (
    input wire clk,
    input wire reset,

    input wire sw_time_set,
    input wire btn_next,
    input wire up_count,
    input wire down_count,
    input wire clock_mode,

    output wire [6:0] c_msec,
    output wire [5:0] c_sec,
    output wire [5:0] c_min,
    output wire [4:0] c_hour,
    output reg  [3:0] led
);
    wire tick_100hz;

    tick_gen_100hz U_tick_gen (
        .clk         (clk),
        .reset       (reset),
        .i_run_stop  (1'b1),
        .o_tick_100hz(tick_100hz)
    );

    wire [1:0] sel;
    select_unit U_SEL (
        .clk     (clk),
        .reset   (reset),
        .en      (sw_time_set && clock_mode),
        .btn_next(btn_next),
        .sel     (sel)
    );

    wire en_tick = !(sw_time_set && clock_mode);

    wire sec_tick, min_tick, hour_tick;

    wire [6:0] msec;
    set_counter #(
        .WIDTH(7),
        .MAX  (100)
    ) U_MSEC (
        .clk    (clk),
        .reset  (reset),
        .en_tick(en_tick),
        .i_tick (tick_100hz),
        .o_tick (sec_tick),
        .count  (msec),

        .set_en(sw_time_set && clock_mode),
        .sel_me(sel == 2'b00),
        .up    (up_count),
        .down  (down_count)
    );

    wire [5:0] sec;
    set_counter #(
        .WIDTH(6),
        .MAX  (60)
    ) U_SEC (
        .clk    (clk),
        .reset  (reset),
        .en_tick(en_tick),
        .i_tick (sec_tick),
        .o_tick (min_tick),
        .count  (sec),

        .set_en(sw_time_set && clock_mode),
        .sel_me(sel == 2'b01),
        .up    (up_count),
        .down  (down_count)
    );

    wire [5:0] min;
    set_counter #(
        .WIDTH(6),
        .MAX  (60)
    ) U_MIN (
        .clk    (clk),
        .reset  (reset),
        .en_tick(en_tick),
        .i_tick (min_tick),
        .o_tick (hour_tick),
        .count  (min),

        .set_en(sw_time_set && clock_mode),
        .sel_me(sel == 2'b10),
        .up    (up_count),
        .down  (down_count)
    );

    wire [4:0] hour;
    set_counter #(
        .WIDTH(5),
        .MAX  (24)
    ) U_HOUR (
        .clk    (clk),
        .reset  (reset),
        .en_tick(en_tick),
        .i_tick (hour_tick),
        .o_tick (),
        .count  (hour),

        .set_en(sw_time_set && clock_mode),
        .sel_me(sel == 2'b11),
        .up    (up_count),
        .down  (down_count)
    );

    assign c_msec = msec;
    assign c_sec  = sec;
    assign c_min  = min;
    assign c_hour = hour;

    always @(*) begin
        if (reset) led = 4'b0000;
        else begin
            case (sel)
                2'b00: led = 4'b0001;
                2'b01: led = 4'b0010;
                2'b10: led = 4'b0100;
                2'b11: led = 4'b1000;
            endcase
        end
    end

endmodule

module select_unit (
    input  wire       clk,
    input  wire       reset,
    input  wire       en,
    input  wire       btn_next,
    output reg  [1:0] sel
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sel <= 2'b00;
        end else if (en && btn_next) begin
            sel <= sel + 2'b01;
        end
    end
endmodule

module set_counter #(
    parameter WIDTH = 7,
    parameter MAX   = 100
) (
    input wire clk,
    input wire reset,

    input  wire             en_tick,
    input  wire             i_tick,
    output reg              o_tick,
    output wire [WIDTH-1:0] count,

    input wire set_en,
    input wire sel_me,
    input wire up,
    input wire down
);

    reg [WIDTH-1:0] counter_reg, counter_next;
    assign count = counter_reg;

    always @(*) begin
        o_tick = 1'b0;
        if (en_tick && i_tick) begin
            if (counter_reg == (MAX - 1)) o_tick = 1'b1;
        end
    end

    always @(*) begin
        counter_next = counter_reg;

        if (set_en && sel_me) begin
            if (up && !down) begin
                if (counter_reg == (MAX - 1)) counter_next = 0;
                else counter_next = counter_reg + 1'b1;
            end else if (down && !up) begin
                if (counter_reg == 0) counter_next = (MAX - 1);
                else counter_next = counter_reg - 1'b1;
            end
        end else if (en_tick && i_tick) begin
            if (counter_reg == (MAX - 1)) counter_next = 0;
            else counter_next = counter_reg + 1'b1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) counter_reg <= 0;
        else counter_reg <= counter_next;
    end

endmodule


