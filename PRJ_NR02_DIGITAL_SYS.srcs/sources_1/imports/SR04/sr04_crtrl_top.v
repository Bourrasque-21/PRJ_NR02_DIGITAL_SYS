`timescale 1ns / 1ps

module sr04_ctrl_top (
    input         clk,
    input         reset,
    input         echo,
    input         sr04_start,
    output        trig,
    output [12:0] distance
);

    wire w_tick_1us;

    tick_gen_1us U_TICK_1us (
        .clk    (clk),
        .reset  (reset),
        .clk_1us(w_tick_1us)
    );

    sr04_ctrl U_SR04 (
        .clk     (clk),
        .reset   (reset),
        .tick_1  (w_tick_1us),
        .start   (sr04_start),
        .echo    (echo),
        .trig    (trig),
        .distance(distance)
    );

endmodule

module sr04_ctrl (
    input             clk,
    input             reset,
    input             tick_1,
    input             start,
    input             echo,
    output reg        trig,
    output reg [12:0] distance
);

    //============================================================
    // FSM States
    // IDLE_S   : Wait for start request
    // TRIG_S   : Drive TRIG high for 10us
    // WAIT_S   : Wait for ECHO rising edge (start of echo pulse)
    // CALC_S   : Count ECHO high width in microseconds
    // CALC_S2  : Convert echo_cnt(us) to distance(cm) by /58
    //============================================================
    localparam IDLE_S = 3'd0, TRIG_S = 3'd1, WAIT_S = 3'd2, CALC_S = 3'd3, CALC_S2 = 3'd4;

    parameter TIMEOUT_WAIT = 30000; // maximum waiting time for echo_rise
    parameter TIMEOUT_CALC = 25000; // maximum time allowed while measuring echo high width

    reg [ 2:0] c_state;
    reg [ 3:0] trig_cnt;
    reg [14:0] echo_cnt;
    reg [14:0] timeout_cnt;
    reg [18:0] distance_x10;
    reg [18:0] distance_div;

    reg echo_n, echo_f;
    reg edge_reg, echo_rise, echo_fall;

    wire echo_sync;

    assign echo_sync = echo_n;

    // Synchronizer for async ECHO
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_f <= 1'b0;
            echo_n <= 1'b0;
        end else begin
            echo_f <= echo;
            echo_n <= echo_f;
        end
    end

    // Edge detection
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

    // Main FSM
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state      <= IDLE_S;
            trig         <= 1'b0;
            distance     <= 13'd0;
            trig_cnt     <= 4'd0;
            echo_cnt     <= 15'd0;
            timeout_cnt  <= 15'd0;
            distance_x10 <= 19'd0;
            distance_div <= 19'd0;
        end else begin
            case (c_state)

                // initialize counters and wait for start
                IDLE_S: begin
                    trig         <= 1'b0;
                    trig_cnt     <= 4'd0;
                    echo_cnt     <= 15'd0;
                    timeout_cnt  <= 15'd0;
                    distance_x10 <= 19'd0;
                    distance_div <= 19'd0;
                    if (start) begin
                        trig    <= 1'b1;
                        c_state <= TRIG_S;
                    end
                end

                // keep TRIG high for 10us
                TRIG_S: begin
                    trig <= 1'b1;
                    if (tick_1) begin
                        if (trig_cnt == 4'd10) begin
                            trig        <= 1'b0;
                            trig_cnt    <= 4'd0;
                            timeout_cnt <= 15'd0;
                            c_state     <= WAIT_S;
                        end else begin
                            trig_cnt <= trig_cnt + 1;
                        end
                    end
                end

                // Wait for ECHO rising edge, If TIMEOUT_WAIT, return IDLE
                WAIT_S: begin
                    if (echo_rise) begin
                        echo_cnt    <= 15'd0;
                        timeout_cnt <= 15'd0;
                        c_state     <= CALC_S;
                    end else begin
                        if (tick_1) begin
                            if (timeout_cnt >= TIMEOUT_WAIT - 1) begin
                                distance <= 13'd0;
                                c_state  <= IDLE_S;
                            end else begin
                                timeout_cnt <= timeout_cnt + 1;
                            end
                        end
                    end
                end

                // Measure echo high duration(ms)
                CALC_S: begin
                    if (echo_fall) begin
                        distance_x10 <= echo_cnt * 10; // for fixed-point scaling XXX.X cm
                        distance_div <= 19'd0;
                        c_state <= CALC_S2;
                    end else if (tick_1) begin
                        echo_cnt <= echo_cnt + 1;
                        if (timeout_cnt >= TIMEOUT_CALC - 1) begin
                            distance <= 13'd0;
                            c_state  <= IDLE_S;
                        end else begin
                            timeout_cnt <= timeout_cnt + 1;
                        end
                    end
                end
                
                // Convert time(us) to distance(cm)
                // distance(cm) = echo_time(us) / 58
                // Replaced direct division with iterative subtraction
                // to avoid 'NEGATIVE SLACK'
                CALC_S2: begin
                    if (distance_x10 >= 19'd58) begin
                        distance_x10 <= distance_x10 - 19'd58; // subtract 58
                        distance_div <= distance_div + 1'b1; // quotient++
                    end else begin
                        distance <= distance_div;
                        c_state  <= IDLE_S;
                    end
                end
                default: c_state <= IDLE_S;
            endcase
        end
    end

endmodule

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
