`timescale 1ns / 1ps

module btn_debounce (
    input  wire clk,
    input  wire reset,
    input  wire i_btn,
    output wire o_btn
);

    parameter CLK_DIV = 100_000;
    parameter F_COUNT = 100_000_000 / CLK_DIV;

    reg [$clog2(F_COUNT)-1:0] counter_reg;
    reg                       clk_100khz_reg;

    reg  [7:0] q_reg;
    wire [7:0] q_next;
    wire       debounce;

    reg edge_reg;

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

    assign q_next = {i_btn, q_reg[7:1]};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            q_reg <= 8'b0;
        end else if (clk_100khz_reg) begin
            q_reg <= q_next;
        end
    end

    assign debounce = &q_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            edge_reg <= 1'b0;
        end else begin
            edge_reg <= debounce;
        end
    end

    assign o_btn = debounce & (~edge_reg);

endmodule