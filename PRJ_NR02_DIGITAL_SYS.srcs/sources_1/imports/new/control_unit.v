`timescale 1ns / 1ps

module control_unit (
    input  wire       clk,
    input  wire       reset,

    input  wire [2:0] mode_sw,
    input  wire       i_run_stop,
    input  wire       i_clear,
    input  wire       cu_btn_5,

    output wire       o_mode_sw,
    output reg        o_run_stop,
    output reg        o_clear,

    output wire       clock_mode,
    output wire       time_set_mode,

    output wire       clk_next,
    output wire       clk_up,
    output wire       clk_down
);

    assign o_mode_sw  = mode_sw[0]; // Stopwatch mode UP/DOWN
    assign clock_mode = mode_sw[1]; // 0: stopwatch, 1: clock

    assign time_set_mode = mode_sw[1] & mode_sw[2]; // Enable time-set mode only when in clock mode

    assign clk_up   = i_run_stop & time_set_mode; // Active only in time-setting mode
    assign clk_down = i_clear    & time_set_mode; // btn_8, btn_2, btn_5
    assign clk_next = cu_btn_5   & time_set_mode; //

    wire sw_runstop_in = i_run_stop & ~clock_mode; // Ignore stopwatch input in clock mode
    wire sw_clear_in   = i_clear    & ~clock_mode; //

    localparam STOP  = 2'b00;
    localparam RUN   = 2'b01;
    localparam CLEAR = 2'b10;

    reg [1:0] current_st, next_st;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_st <= STOP;
        end else begin
            current_st <= next_st;
        end
    end

    always @(*) begin
        next_st    = current_st;
        o_run_stop = 1'b0;
        o_clear    = 1'b0;

        case (current_st)
            STOP: begin

                if (sw_runstop_in) next_st = RUN;
                else if (sw_clear_in) next_st = CLEAR;
            end

            RUN: begin

                o_run_stop = 1'b1;
                if (sw_runstop_in) next_st = STOP;
            end

            CLEAR: begin

                o_clear = 1'b1;
                next_st = STOP;
            end

            default: begin
                next_st = STOP;
            end
        endcase
    end

endmodule

