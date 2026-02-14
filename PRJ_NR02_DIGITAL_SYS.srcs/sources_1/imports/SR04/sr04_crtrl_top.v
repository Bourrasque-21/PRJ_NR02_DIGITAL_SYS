`timescale 1ns / 1ps

module sr04_ctrl_top (
    input        clk,
    input        reset,
    input        echo,
    input        start,
    output       trig,
    output [7:0] fnd_data,
    output [3:0] fnd_digit
);

    wire w_start;
    wire w_tick_1us;
    wire w_timeout;

    wire [12:0] d;
    wire [5:0] w_dist_m = d / 100;
    wire [6:0] w_dist_c = d % 100;

    btn_debounce U_BTN_SR04 (
        .clk  (clk),
        .reset(reset),
        .i_btn(start),
        .o_btn(w_start)
    );

    tick_gen_1us U_TICK_1us (
        .clk    (clk),
        .reset  (reset),
        .clk_1us(w_tick_1us)
    );

    sr04_ctrl U_SR04 (
        .clk     (clk),
        .reset   (reset),
        .tick_1  (w_tick_1us),
        .start   (w_start),
        .echo    (echo),
        .trig    (trig),
        .distance(d),
        .timeout (w_timeout)
    );

    // =================
    // FND
    // =================
    fnd_contr U_FND_CTRL (
        .clk          (clk),
        .reset        (reset),
        .sel_display  (1'b0),
        .sel_display_2(1'b0),
        .decimal_mode (1'b1),
        .show_error   (w_timeout),
        .fnd_in_data  ({7'b0, 6'b0, w_dist_m, w_dist_c}),
        .fnd_in_data_2(25'd0),
        .fnd_digit    (fnd_digit),
        .fnd_data     (fnd_data)
    );
endmodule


// =================
// SR04 Module
// =================
module sr04_ctrl (
    input            clk,
    input            reset,
    input            tick_1,
    input            start,
    input            echo,
    output reg       trig,
    output reg [12:0] distance,
    output reg       timeout
);

    localparam IDLE_S = 2'b00, TRIG_S = 2'b01, WAIT_S = 2'b10, CALC_S = 2'b11;

    parameter TIMEOUT_WAIT = 30000;
    parameter TIMEOUT_CALC = 25000;

    reg [ 1:0] c_state;
    reg [ 3:0] trig_cnt;
    reg [14:0] echo_cnt;
    reg [14:0] timeout_cnt;

    reg echo_n, echo_f;
    reg edge_reg, echo_rise, echo_fall;
   
    wire echo_sync;
   
    assign echo_sync = echo_n;

    // ===================================
    // Synchronizer
    // ===================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_f <= 1'b0;
            echo_n <= 1'b0;
        end else begin
            echo_f <= echo;
            echo_n <= echo_f;
        end
    end

    // ===================================
    // Edge detector
    // ===================================
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            edge_reg  <= 1'b0;
            echo_rise <= 1'b0;
            echo_fall <= 1'b0;
        end else begin
            echo_rise <= (~edge_reg) & echo_sync;
            echo_fall <= edge_reg & (~echo_sync);
            edge_reg  <= echo_sync;
        end
    end

    // ===================================
    // FSM
    // ===================================
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state     <= IDLE_S;
            trig        <= 1'b0;
            distance    <= 13'd0;
            timeout     <= 1'b0;
            trig_cnt    <= 4'd0;
            echo_cnt    <= 14'd0;
            timeout_cnt <= 15'd0;
        end else begin
            case (c_state)
                IDLE_S: begin
                    trig        <= 1'b0;
                    trig_cnt    <= 4'd0;
                    echo_cnt    <= 14'd0;
                    timeout_cnt <= 15'd0;
                    if (start) begin
                        trig    <= 1'b1;
                        timeout <= 1'b0;
                        c_state <= TRIG_S;
                    end
                end

                TRIG_S: begin
                    trig <= 1'b1;
                    if (tick_1) begin
                        if (trig_cnt == 4'd10) begin  // 11us
                            trig        <= 1'b0;
                            trig_cnt    <= 4'd0;
                            timeout_cnt <= 15'd0;
                            c_state     <= WAIT_S;
                        end else begin
                            trig_cnt <= trig_cnt + 1;
                        end
                    end
                end

                WAIT_S: begin
                    if (echo_rise) begin
                        echo_cnt    <= 15'd0;
                        timeout_cnt <= 15'd0;
                        c_state     <= CALC_S;
                    end else begin
                        if (tick_1) begin
                            if (timeout_cnt >= TIMEOUT_WAIT - 1) begin
                                distance <= 13'd0;
                                timeout  <= 1'b1;
                                c_state  <= IDLE_S;
                            end else begin
                                timeout_cnt <= timeout_cnt + 1;
                            end
                        end
                    end
                end

                CALC_S: begin
                    if (echo_fall) begin
                        distance <= (echo_cnt * 10) / 58;
                        timeout  <= 1'b0;
                        c_state  <= IDLE_S;
                    end else if (tick_1) begin
                        echo_cnt <= echo_cnt + 1;
                        if (timeout_cnt >= TIMEOUT_CALC - 1) begin
                            distance <= 13'd0;
                            timeout  <= 1'b1;
                            c_state  <= IDLE_S;
                        end else begin
                            timeout_cnt <= timeout_cnt + 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule



// ===================================
// tick gen 1usec
// ===================================
module tick_gen_1us (
    input      clk,
    input      reset,
    output reg clk_1us
);
    reg [6:0] count_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count_reg <= 0;
            clk_1us   <= 1'b0;
        end else if (count_reg == 99) begin
            count_reg <= 0;
            clk_1us   <= 1'b1;
        end else begin
            count_reg <= count_reg + 1;
            clk_1us   <= 1'b0;
        end
    end
endmodule
