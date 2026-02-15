`timescale 1ns / 1ps

module fnd_contr (
    input  wire        clk,
    input  wire        reset,

    input  wire        sel_display,
    input  wire  [1:0] sel_display_2,

    input  wire [25:0] fnd_in_data,
    input  wire [23:0] fnd_in_data_2,

    input wire  [25:0] fnd_dist_data,
    input wire  [25:0] fnd_dht_data,

    output wire [3:0]  fnd_digit,
    output wire [7:0]  fnd_data
);

    wire [25:0] time_sel;

    mux_4x1_set U_MODE_SEL (
        .sel   (sel_display_2),
        .i_sel0(fnd_in_data),
        .i_sel1({2'b00, fnd_in_data_2}),
        .i_sel2(fnd_dist_data),
        .i_sel3(fnd_dht_data),
        .o_mux (time_sel)
    );

    wire in_dist = (sel_display_2 == 2'b10);
    wire in_dht  = (sel_display_2 == 2'b11);

    wire [3:0] bcd_3 = time_sel[15:12];
    wire [3:0] bcd_2 = time_sel[11:8];
    wire [3:0] bcd_1 = time_sel[7:4];
    wire [3:0] bcd_0 = time_sel[3:0];
    wire [3:0] sr_dth_o;
    wire       clk_1khz;
    wire [2:0] digit_sel;

    mux_8x1 U_MUX_SR_DTH (
        .sel           (digit_sel),
        .digit_1       (bcd_0),
        .digit_10      (bcd_1),
        .digit_100     (bcd_2),
        .digit_1000    (bcd_3),
        .digit_dot_1   (4'hf),
        .digit_dot_10  ((in_dht) ? 4'hE : (sel_display == 1'b0) ? 4'hE : 4'hf),
        .digit_dot_100 (4'hf),
        .digit_dot_1000(4'hf),
        .mux_out       (sr_dth_o)
    );

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

    decoder2x4 U_DECODER (
        .dec_in (digit_sel[1:0]),
        .dec_out(fnd_digit)
    );

    wire dot_onoff;

    dot_onoff_comp U_DOT_COMP (
        .msec     (time_sel[6:0]),
        .dot_onoff(dot_onoff)
    );

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

    wire [3:0] bcd_nibble;
    mux_2x1 U_PAGE_SEL (
        .sel   (sel_display),
        .i_sel0(sc_nibble),
        .i_sel1(hm_nibble),
        .o_mux (bcd_nibble)
    );

    wire [3:0] bcd_out_end = (in_dist || in_dht) ? sr_dth_o : bcd_nibble;

    bcd U_BCD (
        .bcd     (bcd_out_end),
        .fnd_data(fnd_data)
    );

endmodule

module mux_2x1 (
    input  wire       sel,
    input  wire [3:0] i_sel0,
    input  wire [3:0] i_sel1,
    output wire [3:0] o_mux
);
    assign o_mux = sel ? i_sel1 : i_sel0;
endmodule

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

            4'd14: fnd_data = 8'h7f;
            default: fnd_data = 8'hff;
        endcase
    end
endmodule

module dot_onoff_comp (
    input  wire [6:0] msec,
    output wire       dot_onoff
);
    assign dot_onoff = (msec < 50);
endmodule

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
