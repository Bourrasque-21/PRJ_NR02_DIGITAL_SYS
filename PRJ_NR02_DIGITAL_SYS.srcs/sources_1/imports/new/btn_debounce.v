`timescale 1ns / 1ps

//============================================================
// Module Name : btn_debounce
// Description :
//   - Debounces a mechanical push button input.
//   - Generates a clean single-clock pulse when a valid
//     button press is detected.
//   - Uses a clock divider and an 8-sample shift register
//     to filter out button bouncing.
//
// Operation :
//   1) The system clock is divided to generate a slow
//      sampling clock (~100 kHz).
//   2) The button input is sampled into an 8-bit shift
//      register at the slow clock rate.
//   3) When all 8 samples are '1', the input is considered
//      stable (debounced).
//   4) A rising-edge detector generates a one-clock pulse
//      on a valid button press.
//============================================================
module btn_debounce (
    input  wire clk,     // System clock (e.g. 100 MHz)
    input  wire reset,   // Asynchronous reset (active high)
    input  wire i_btn,   // Raw button input
    output wire o_btn    // One-clock debounced button pulse
);

    // --------------------------------------------------------
    // Clock divider parameters
    // --------------------------------------------------------
    // CLK_DIV = number of system clock cycles per debounce tick
    // Example: 100 MHz / 100,000 = 1 kHz sampling clock
    parameter CLK_DIV = 100_000;
    parameter F_COUNT = 100_000_000 / CLK_DIV;

    // --------------------------------------------------------
    // Registers and wires
    // --------------------------------------------------------
    reg [$clog2(F_COUNT)-1:0] counter_reg; // Clock divider counter
    reg                       clk_100khz_reg; // Debounce sampling clock

    reg  [7:0] q_reg;        // Shift register for input samples
    wire [7:0] q_next;       // Next shift register value
    wire       debounce;     // Debounced (stable) button signal

    reg edge_reg;            // Previous debounce state (edge detect)

    // --------------------------------------------------------
    // Clock divider (generates slow sampling clock)
    // --------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter_reg    <= 0;
            clk_100khz_reg <= 1'b0;
        end else begin
            if (counter_reg == (F_COUNT - 1)) begin
                counter_reg    <= 0;
                clk_100khz_reg <= 1'b1;
            end else begin
                counter_reg    <= counter_reg + 1;
                clk_100khz_reg <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------
    // Shift register for button sampling
    // - Latest button value is shifted into MSB
    // --------------------------------------------------------
    assign q_next = {i_btn, q_reg[7:1]};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            q_reg <= 8'b0;
        end else if (clk_100khz_reg) begin
            q_reg <= q_next;
        end
    end

    // --------------------------------------------------------
    // Debounce logic
    // - Asserted only when all 8 samples are '1'
    // --------------------------------------------------------
    assign debounce = &q_reg;

    // --------------------------------------------------------
    // Rising edge detection on debounced signal
    // --------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            edge_reg <= 1'b0;
        end else begin
            edge_reg <= debounce;
        end
    end

    // --------------------------------------------------------
    // Output pulse generation
    // - Generates a one-clock pulse on debounce rising edge
    // --------------------------------------------------------
    assign o_btn = debounce & (~edge_reg);

endmodule