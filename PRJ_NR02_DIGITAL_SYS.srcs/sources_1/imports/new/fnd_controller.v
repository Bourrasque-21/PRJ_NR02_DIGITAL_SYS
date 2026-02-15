`timescale 1ns / 1ps

//============================================================
// Module Name : fnd_contr
// Description :
//   4-digit 7-segment (FND) display controller with time-source
//   selection and page switching.
//
//   Features
//   - Selects between two input time sources:
//       * fnd_in_data   : 26-bit stopwatch time (HH:MM:SS:CC style)
//       * fnd_in_data_2 : 24-bit clock time
//     sel_display_2 selects which source is displayed.
//
//   - Splits each time field into 2 decimal digits (ones/tens).
//
//   - Multiplexes digits at ~1 kHz refresh using a 3-bit scan counter.
//     * digit_sel[1:0] selects which of the 4 digits is active.
//     * digit_sel[2] is used for optional "dot/blank" pages.
//
//   - sel_display selects which page is shown on the 4-digit display:
//       * 0: Sec : Centi-sec (or Sec : mSec) page
//       * 1: Hour : Min page
//
//   - Provides a blinking dot indicator based on the centi-second field
//     (msec < 50 => dot ON), used as a simple heartbeat.
//============================================================
module fnd_contr (
    input  wire        clk,
    input  wire        reset,

    input  wire        sel_display,    // page select: 0=sec/cc, 1=hour/min
    input  wire  [1:0] sel_display_2,  // source select: 0=stopwatch, 1=clock

    input  wire [25:0] fnd_in_data,     // stopwatch time (packed)
    input  wire [23:0] fnd_in_data_2,   // clock time (packed)

    input wire  [25:0] fnd_dist_data,
    input wire  [25:0] fnd_dht_data,

    output wire [3:0]  fnd_digit,       // digit enable (active-low assumed)
    output wire [7:0]  fnd_data         // segment pattern
);

    // ------------------------------------------------------------
    // 1) Select input source and normalize width to 26 bits
    // ------------------------------------------------------------
    // When selecting the 24-bit clock input, it is already aligned to
    // the same bit packing used by the stopwatch input:
    //   [25:19] hour, [18:13] min, [12:7] sec, [6:0] cc
    wire [25:0] time_sel;

    mux_4x1_set U_MODE_SEL (
        .sel   (sel_display_2),
        .i_sel0(fnd_in_data), // stopwatch: already 26-bit (extra 2 bits kept as 0)
        .i_sel1({2'b00, fnd_in_data_2}),        // clock: 24-bit, treated as 26-bit bus here
        .i_sel2(fnd_dist_data),
        .i_sel3(fnd_dht_data),
        .o_mux (time_sel)
    );

    // -----------------------------------------------------------
    // FND SR04, DHT11
    // -----------------------------------------------------------

    wire in_dist = (sel_display_2 == 2'b10);
    wire in_dht  = (sel_display_2 == 2'b11);

    wire [3:0] bcd_3 = time_sel[15:12];
    wire [3:0] bcd_2 = time_sel[11:8];
    wire [3:0] bcd_1 = time_sel[7:4];
    wire [3:0] bcd_0 = time_sel[3:0];
    wire [3:0] sr_dth_o;

    mux_8x1 U_MUX_SR_DTH (
        .sel           (digit_sel),
        .digit_1       (bcd_0),
        .digit_10      (bcd_1),
        .digit_100     (bcd_2),
        .digit_1000    (bcd_3),
        .digit_dot_1   (4'hf),
        .digit_dot_10  ((sel_display == 1'b0) ? 4'hE : 4'hf),
        .digit_dot_100 (4'hf),
        .digit_dot_1000(4'hf),
        .mux_out       (sr_dth_o)
    );

    // ------------------------------------------------------------
    // 2) Split each field into decimal digits (ones/tens)
    // ------------------------------------------------------------
    wire [3:0] hour_1, hour_10;
    wire [3:0] min_1,  min_10;
    wire [3:0] sec_1,  sec_10;
    wire [3:0] cc_1,   cc_10;

    digit_splitter #(.BIT_WIDTH(7)) U_HOUR_DS (
        .in_data (time_sel[25:19]),
        .digit_1 (hour_1),
        .digit_10(hour_10)
    );

    digit_splitter #(.BIT_WIDTH(6)) U_MIN_DS (
        .in_data (time_sel[18:13]),
        .digit_1 (min_1),
        .digit_10(min_10)
    );

    digit_splitter #(.BIT_WIDTH(6)) U_SEC_DS (
        .in_data (time_sel[12:7]),
        .digit_1 (sec_1),
        .digit_10(sec_10)
    );

    digit_splitter #(.BIT_WIDTH(7)) U_CC_DS (
        .in_data (time_sel[6:0]),
        .digit_1 (cc_1),
        .digit_10(cc_10)
    );

    // ------------------------------------------------------------
    // 3) 1 kHz digit scan clock and digit selector (0..7)
    // ------------------------------------------------------------
    wire       clk_1khz;
    wire [2:0] digit_sel;

    clk_div U_CLK_DIV (
        .clk     (clk),
        .reset   (reset),
        .clk_1khz(clk_1khz)
    );

    counter8 U_COUNTER8 (
        .clk      (clk_1khz),
        .reset    (reset),
        .digit_sel(digit_sel)
    );

    // digit enable (4 digits) uses digit_sel[1:0]
    decoder2x4 U_DECODER (
        .dec_in (digit_sel[1:0]),
        .dec_out(fnd_digit)
    );

    // ------------------------------------------------------------
    // 4) Dot blink generator (based on cc field)
    // ------------------------------------------------------------
    wire dot_onoff;

    dot_onoff_comp U_DOT_COMP (
        .msec     (time_sel[6:0]),
        .dot_onoff(dot_onoff)
    );

    // ------------------------------------------------------------
    // 5) Build display data for two pages:
    //    - Hour:Min page
    //    - Sec:Cc page
    //
    // mux_8x1 uses digit_sel[2:0] to select:
    //   0..3 : actual digits
    //   4..7 : optional "dot/blank" patterns
    // ------------------------------------------------------------
    wire [3:0] hm_nibble;
    wire [3:0] sc_nibble;

    mux_8x1 U_MUX_HOUR_MIN (
        .sel           (digit_sel),
        .digit_1       (min_1),
        .digit_10      (min_10),
        .digit_100     (hour_1),
        .digit_1000    (hour_10),
        .digit_dot_1   (4'hF),
        .digit_dot_10  (4'hF),
        .digit_dot_100 ({3'b111, dot_onoff}),
        .digit_dot_1000(4'hF),
        .mux_out       (hm_nibble)
    );

    mux_8x1 U_MUX_SEC_CC (
        .sel           (digit_sel),
        .digit_1       (cc_1),
        .digit_10      (cc_10),
        .digit_100     (sec_1),
        .digit_1000    (sec_10),
        .digit_dot_1   (4'hF),
        .digit_dot_10  (4'hF),
        .digit_dot_100 ({3'b111, dot_onoff}),
        .digit_dot_1000(4'hF),
        .mux_out       (sc_nibble)
    );

    // Page select: 0 = sec/cc, 1 = hour/min
    wire [3:0] bcd_nibble;
    mux_2x1 U_PAGE_SEL (
        .sel   (sel_display),
        .i_sel0(sc_nibble),
        .i_sel1(hm_nibble),
        .o_mux (bcd_nibble)
    );

    // ------------------------------------------------------------
    // 6) BCD nibble to 7-seg segments
    // ------------------------------------------------------------
    wire [3:0] bcd_out_end = (in_dist || in_dht) ? sr_dth_o : bcd_nibble;

    bcd U_BCD (
        .bcd     (bcd_out_end),
        .fnd_data(fnd_data)
    );

endmodule

//============================================================
// 2-to-1 mux for 4-bit digit selection
//============================================================
module mux_2x1 (
    input  wire       sel,
    input  wire [3:0] i_sel0,
    input  wire [3:0] i_sel1,
    output wire [3:0] o_mux
);
    assign o_mux = sel ? i_sel1 : i_sel0;
endmodule

//============================================================
// Clock divider: generates a ~1 kHz tick from 100 MHz clock.
// Output is a 1-cycle pulse (clk_1khz).
//============================================================
module clk_div (
    input  wire clk,
    input  wire reset,
    output reg  clk_1khz
);
    reg [$clog2(100_000):0] counter_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_r <= 0;
            clk_1khz  <= 1'b0;
        end else if (counter_r == 99_999) begin
            counter_r <= 0;
            clk_1khz  <= 1'b1;
        end else begin
            counter_r <= counter_r + 1;
            clk_1khz  <= 1'b0;
        end
    end
endmodule

//============================================================
// 3-bit counter used for digit scanning (0..7).
//============================================================
module counter8 (
    input  wire       clk,
    input  wire       reset,
    output wire [2:0] digit_sel
);
    reg [2:0] counter_r;

    assign digit_sel = counter_r;

    always @(posedge clk or posedge reset) begin
        if (reset) counter_r <= 0;
        else       counter_r <= counter_r + 1'b1;
    end
endmodule

//============================================================
// 2-to-4 decoder for digit enable signals (active-low).
//============================================================
module decoder2x4 (
    input  wire [1:0] dec_in,
    output reg  [3:0] dec_out
);
    always @(*) begin
        case (dec_in)
            2'd0: dec_out = 4'b1110;
            2'd1: dec_out = 4'b1101;
            2'd2: dec_out = 4'b1011;
            2'd3: dec_out = 4'b0111;
            default: dec_out = 4'b1111;
        endcase
    end
endmodule

//============================================================
// 8-to-1 mux for digit/page selection.
// - sel[1:0] typically selects the 4 digits
// - sel[2] can be used as an extra page/marker
//============================================================
module mux_8x1 (
    input  wire [2:0] sel,
    input  wire [3:0] digit_1,
    input  wire [3:0] digit_10,
    input  wire [3:0] digit_100,
    input  wire [3:0] digit_1000,
    input  wire [3:0] digit_dot_1,
    input  wire [3:0] digit_dot_10,
    input  wire [3:0] digit_dot_100,
    input  wire [3:0] digit_dot_1000,
    output reg  [3:0] mux_out
);
    always @(*) begin
        case (sel)
            3'b000: mux_out = digit_1;
            3'b001: mux_out = digit_10;
            3'b010: mux_out = digit_100;
            3'b011: mux_out = digit_1000;
            3'b100: mux_out = digit_dot_1;
            3'b101: mux_out = digit_dot_10;
            3'b110: mux_out = digit_dot_100;
            3'b111: mux_out = digit_dot_1000;
            default: mux_out = 4'hF;
        endcase
    end
endmodule

//============================================================
// Splits an integer field into two decimal digits (ones/tens).
//============================================================
module digit_splitter #(
    parameter BIT_WIDTH = 7
) (
    input  wire [BIT_WIDTH-1:0] in_data,
    output wire [3:0]           digit_1,
    output wire [3:0]           digit_10
);
    assign digit_1  = in_data % 10;
    assign digit_10 = (in_data / 10) % 10;
endmodule

//============================================================
// BCD to 7-segment decoder (common-anode/cathode depends on board).
// Here, the segment encoding matches the user's hardware mapping.
//============================================================
module bcd (
    input  wire [3:0] bcd,
    output reg  [7:0] fnd_data
);
    always @(*) begin
        case (bcd)
            4'd0:  fnd_data = 8'hc0;
            4'd1:  fnd_data = 8'hf9;
            4'd2:  fnd_data = 8'ha4;
            4'd3:  fnd_data = 8'hb0;
            4'd4:  fnd_data = 8'h99;
            4'd5:  fnd_data = 8'h92;
            4'd6:  fnd_data = 8'h82;
            4'd7:  fnd_data = 8'hf8;
            4'd8:  fnd_data = 8'h80;
            4'd9:  fnd_data = 8'h90;
            4'd10: fnd_data = 8'h92;
            4'd11: fnd_data = 8'hAf;

            // Non-decimal codes
            4'd14: fnd_data = 8'h7f; // example: dot/marker
            default: fnd_data = 8'hff; // blank
        endcase
    end
endmodule

//============================================================
// Dot blink comparator (simple heartbeat using centi-second field).
//============================================================
module dot_onoff_comp (
    input  wire [6:0] msec,
    output wire       dot_onoff
);
    assign dot_onoff = (msec < 50);
endmodule

//============================================================
// 2-to-1 mux for selecting packed time data (26-bit wide).
//============================================================
module mux_4x1_set (
    input  wire  [1:0] sel,
    input  wire [25:0] i_sel0,
    input  wire [25:0] i_sel1,
    input  wire [25:0] i_sel2,
    input  wire [25:0] i_sel3,
    output wire [25:0] o_mux
);
    assign o_mux = (sel == 2'b00) ? i_sel0 :
                   (sel == 2'b01) ? i_sel1 :
                   (sel == 2'b10) ? i_sel2 :
                                    i_sel3;

endmodule
