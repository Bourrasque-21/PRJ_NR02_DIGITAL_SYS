`timescale 1ns / 1ps

//============================================================
// Module Name : top_stopwatch_watch
// Description :
//   Top-level integration of:
//     - Stopwatch datapath
//     - Clock (timekeeping) datapath with time-set feature
//     - 7-segment (FND) display controller
//     - UART interface for PC control and time query ('Q')
//
//   Input Sources
//   - Physical push buttons (btn_8, btn_5, btn_2) are debounced.
//   - UART can generate virtual button pulses (R/N/C) and PC-mode
//     switch overrides (M, 0~3).
//
//   Mode Switch Map (mode_sw[3:0])
//   - [0] : Stopwatch count direction (0=up, 1=down)
//   - [1] : 0=Stopwatch mode, 1=Clock mode
//   - [2] : FND page select (0=sec/cc, 1=hour/min)
//   - [3] : Time-set enable (effective only in Clock mode)
//
//   Key Behavior
//   - In PC control mode, mode_sw_com is overridden by pc_mode_sw.
//   - In Clock + Time-set mode, buttons are re-mapped:
//       btn_8 -> clk_up, btn_2 -> clk_down, btn_5 -> clk_next
//   - In Stopwatch mode, buttons control run/stop and clear.
//============================================================
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

    // ------------------------------------------------------------
    // Internal time buses
    // ------------------------------------------------------------
    wire [25:0] w_stopwatch_time; // {hour[25:19], min[18:13], sec[12:7], cc[6:0]}
    wire [23:0] w_clock_time;  // {hour[23:19], min[18:13], sec[12:7], cc[6:0]}
    wire [12:0] w_distance;
    // Stopwatch mode select (direction)
    wire w_mode;

    // ------------------------------------------------------------
    // Debounced button signals (physical)
    // ------------------------------------------------------------
    wire i_btn_8;
    wire i_btn_5;
    wire i_btn_2;
    wire w_sr04_btn;
    // ------------------------------------------------------------
    // Clock control signals (time-set)
    // ------------------------------------------------------------
    wire clock_mode;
    wire time_set_mode;
    wire clk_next, clk_up, clk_down;

    // ------------------------------------------------------------
    // UART-generated virtual button pulses (R/N/C)
    // ------------------------------------------------------------
    wire       or_btn_r;
    wire       or_btn_n;
    wire       or_btn_c;

    // ------------------------------------------------------------
    // PC control mode (switch override)
    // ------------------------------------------------------------
    wire       pc_ctrl_mode;
    wire [4:0] pc_mode_sw;

    // ------------------------------------------------------------
    // Combined inputs (UART OR physical)
    // ------------------------------------------------------------
    wire       i_run_stop;  // Run/Stop in stopwatch or Up in time-set
    wire       i_clear;  // Clear in stopwatch or Down in time-set
    wire       cu_btn_5;  // Next select in time-set
    wire [4:0] mode_sw_com;  // final mode switches after PC override

    wire [1:0] w_led_sel = {mode_sw_com[4], mode_sw_com[1]};
    wire [3:0] w_clk_sel_led;

    wire [5:0] w_dist_m = w_distance / 100;
    wire [6:0] w_dist_c = w_distance % 100;

    assign i_run_stop = or_btn_r | i_btn_8;
    assign i_clear = or_btn_c | i_btn_2;
    assign cu_btn_5 = or_btn_n | i_btn_5;

    // PC mode override mux
    assign mode_sw_com = pc_ctrl_mode ? pc_mode_sw : mode_sw;
    assign pc_mode_led = pc_ctrl_mode;

    // time-set 우선, 아니면 소스 표시
    assign out_led = (w_led_sel == 2'b11) ? 4'b0011 :  // 11
                     (w_led_sel == 2'b10) ? 4'b0010 :  // 10
                     (w_led_sel == 2'b01) ? (time_set_mode ? w_clk_sel_led : 4'b0001)  // 01
                                          : 4'b0000;  // 00


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
        .o_btn(w_sr04_btn)
    );

    // ------------------------------------------------------------
    // UART top: receives commands + can transmit clock time on 'Q'
    // ------------------------------------------------------------
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

        // Clock time input for ASCII time transmit
        .clock_time24(w_clock_time)
    );

    // ------------------------------------------------------------
    // Clock datapath (runs continuously; time-set gates ticking)
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Button debounce blocks (physical)
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // Control unit: stopwatch FSM + clock/time-set button mapping
    // ------------------------------------------------------------
    wire o_btn_8;  // stopwatch run enable (level)
    wire o_btn_2;  // stopwatch clear pulse

    control_unit U_CONTROL_UNIT (
        .clk    (clk),
        .reset  (reset),
        .mode_sw(mode_sw_com[3:0]),

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

    // ------------------------------------------------------------
    // Stopwatch datapath
    // ------------------------------------------------------------
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

    // ------------------------------------------------------------
    // 7-seg display controller
    // - sel_display    : selects page within the selected time source
    // - sel_display_2  : selects time source (clock vs stopwatch)
    // ------------------------------------------------------------
    fnd_contr U_FND_CTRL (
        .clk          (clk),
        .reset        (reset),
        .sel_display  (mode_sw_com[2]),
        .sel_display_2({mode_sw_com[4], mode_sw_com[1]}),
        .fnd_in_data  (w_stopwatch_time),
        .fnd_in_data_2(w_clock_time),
        .fnd_dist_data({13'd0, w_dist_m, w_dist_c}),
        .fnd_dht_data (26'd0),
        .fnd_digit    (fnd_digit),
        .fnd_data     (fnd_data)
    );

endmodule

//============================================================
// Stopwatch datapath
// - Cascaded counters: cc(0..99) -> sec(0..59) -> min(0..59) -> hour(0..99)
// - Supports up/down counting based on mode_sw
// - run_stop gates counting; clear resets all counters
//============================================================
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

    // 100 Hz tick (10 ms period)
    tick_gen_100hz U_tick_gen (
        .clk         (clk),
        .reset       (reset),
        .i_run_stop  (run_stop),
        .o_tick_100hz(w_tick_100hz)
    );

    // hour: 0..99
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

    // min: 0..59
    tick_counter #(
        .BIT_WIDTH(7),
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

    // sec: 0..59
    tick_counter #(
        .BIT_WIDTH(7),
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

    // cc (centi-second): 0..99
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

//============================================================
// Generic tick-driven counter
// - If run_stop=1 and i_tick pulses, counter updates.
// - mode=0: up-count, mode=1: down-count
// - o_tick pulses when the counter wraps.
//============================================================
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
            // mode=1: down count
            if (mode) begin
                if (counter_reg == 0) begin
                    counter_next = TIMES - 1;
                    o_tick       = 1'b1;
                end else begin
                    counter_next = counter_reg - 1'b1;
                end
            end  // mode=0: up count
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

//============================================================
// 100 Hz tick generator (1-cycle pulse when enabled)
//============================================================
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

//============================================================
// Clock datapath with time-set mode
// - Normal mode: ticks at 100 Hz and cascades up to hour.
// - Time-set mode: disables tick (en_tick=0) and allows manual
//   up/down edits on the selected field.
// - LED shows current selection (hour/min/sec/cc) when time-set.
//============================================================
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

    // Select which field to edit (only active in clock + time-set)
    wire [1:0] sel;
    select_unit U_SEL (
        .clk     (clk),
        .reset   (reset),
        .en      (sw_time_set && clock_mode),
        .btn_next(btn_next),
        .sel     (sel)
    );

    // Disable tick while time-setting (freeze time)
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

    // LED indication:
    // - Off in stopwatch mode
    // - All on in normal clock mode
    // - One-hot indicates selected field in time-set mode
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

//============================================================
// Selection unit for time-set mode (cycles through 4 fields)
//============================================================
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

//============================================================
// Counter with two modes:
//  - Normal tick counting (en_tick && i_tick)
//  - Manual set mode (set_en && sel_me) using up/down pulses
//============================================================
module set_counter #(
    parameter WIDTH = 7,
    parameter MAX   = 100
) (
    input wire clk,
    input wire reset,

    // normal count
    input  wire             en_tick,
    input  wire             i_tick,
    output reg              o_tick,
    output wire [WIDTH-1:0] count,

    // time-set
    input wire set_en,
    input wire sel_me,
    input wire up,
    input wire down
);

    reg [WIDTH-1:0] counter_reg, counter_next;
    assign count = counter_reg;

    // o_tick for normal counting only (wrap indicator)
    always @(*) begin
        o_tick = 1'b0;
        if (en_tick && i_tick) begin
            if (counter_reg == (MAX - 1)) o_tick = 1'b1;
        end
    end

    // next-state logic
    always @(*) begin
        counter_next = counter_reg;

        // manual time-set has priority over normal ticking
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

    // register
    always @(posedge clk or posedge reset) begin
        if (reset) counter_reg <= 0;
        else counter_reg <= counter_next;
    end

endmodule


