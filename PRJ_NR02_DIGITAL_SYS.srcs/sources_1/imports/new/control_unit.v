`timescale 1ns / 1ps

//============================================================
// Module Name : control_unit
// Description :
//   Top-level control logic for the integrated Stopwatch/Clock
//   system.
//
//   - Decodes mode switches (mode_sw) to select Clock vs Stopwatch.
//   - In Clock mode:
//       * Enables Time-Set mode (mode_sw[3]).
//       * Re-maps buttons to time setting controls:
//           - i_run_stop -> clk_up
//           - i_clear    -> clk_down
//           - cu_btn_5   -> clk_next
//       * Disables stopwatch run/clear commands.
//   - In Stopwatch mode:
//       * Runs a simple FSM to generate run/stop and clear controls.
//
// Switch Map (mode_sw):
//   [0] : Stopwatch count direction (0=up, 1=down) -> o_mode_sw
//   [1] : Mode select (0=Stopwatch, 1=Clock)       -> clock_mode
//   [3] : Time-set enable (effective only in clock_mode)
//============================================================
module control_unit (
    input  wire       clk,
    input  wire       reset,

    input  wire [3:0] mode_sw,     // mode switches
    input  wire       i_run_stop,  // button input (Run/Stop in stopwatch, Up in time-set)
    input  wire       i_clear,     // button input (Clear in stopwatch, Down in time-set)
    input  wire       cu_btn_5,    // button input (unused in stopwatch, Next in time-set)

    output wire       o_mode_sw,   // stopwatch up/down mode
    output reg        o_run_stop,  // stopwatch run enable (level)
    output reg        o_clear,     // stopwatch clear pulse (1-cycle)

    output wire       clock_mode,     // 1: clock mode, 0: stopwatch mode
    output wire       time_set_mode,  // 1: clock + time-set enabled

    output wire       clk_next,    // time-set select next field
    output wire       clk_up,      // time-set increment
    output wire       clk_down     // time-set decrement
);

    // --------------------------------------------------------
    // Mode decoding
    // --------------------------------------------------------
    assign o_mode_sw  = mode_sw[0];       // stopwatch direction (up/down)
    assign clock_mode = mode_sw[1];       // mode select: clock vs stopwatch

    // Time setting is only valid when clock mode is active.
    assign time_set_mode = mode_sw[1] & mode_sw[3];

    // --------------------------------------------------------
    // Button mapping in time-set mode (clock mode only)
    // --------------------------------------------------------
    // In time-set mode, the same physical buttons act as Up/Down/Next.
    assign clk_up   = i_run_stop & time_set_mode;
    assign clk_down = i_clear    & time_set_mode;
    assign clk_next = cu_btn_5   & time_set_mode;

    // --------------------------------------------------------
    // Stopwatch inputs are ignored while in clock mode
    // --------------------------------------------------------
    wire sw_runstop_in = i_run_stop & ~clock_mode;
    wire sw_clear_in   = i_clear    & ~clock_mode;

    // --------------------------------------------------------
    // Stopwatch FSM
    // States:
    //   STOP  : stopwatch stopped
    //   RUN   : stopwatch running (o_run_stop=1)
    //   CLEAR : generate clear pulse then return to STOP
    // --------------------------------------------------------
    localparam STOP  = 2'b00;
    localparam RUN   = 2'b01;
    localparam CLEAR = 2'b10;

    reg [1:0] current_st, next_st;

    // State register
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_st <= STOP;
        end else begin
            current_st <= next_st;
        end
    end

    // Next-state / output logic (Moore-style outputs)
    always @(*) begin
        next_st    = current_st;
        o_run_stop = 1'b0;
        o_clear    = 1'b0;

        case (current_st)
            STOP: begin
                // Default: stopped, no clear
                if (sw_runstop_in) next_st = RUN;
                else if (sw_clear_in) next_st = CLEAR;
            end

            RUN: begin
                // Running while in RUN state
                o_run_stop = 1'b1;
                if (sw_runstop_in) next_st = STOP;
            end

            CLEAR: begin
                // One-cycle clear pulse, then back to STOP
                o_clear = 1'b1;
                next_st = STOP;
            end

            default: begin
                next_st = STOP;
            end
        endcase
    end

endmodule