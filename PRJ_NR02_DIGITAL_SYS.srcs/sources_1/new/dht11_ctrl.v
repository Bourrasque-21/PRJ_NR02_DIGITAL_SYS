`timescale 1ns / 1ps

module dht11_top (
    input clk,
    input reset,
    input dht11_btn_start,

    output [15:0] dht11_ht_data,
    output [15:0] dht11_temp_data,
    output dht11_valid,
    output dht11_done,

    inout dhtio
);

    wire w_btn_s;
    
    btn_debounce U_BTN (
        .clk  (clk),
        .reset(reset),
        .i_btn(dht11_btn_start),
        .o_btn(w_btn_s)
    );

    dht11_controller U_DHT11 (
        .clk(clk),
        .reset(reset),
        .start(w_btn_s),
        .ht(dht11_ht_data),
        .temp(dht11_temp_data),
        .dht11_done(dht11_done),
        .dht11_valid(dht11_valid),
        .dhtio(dhtio)
    );
endmodule




module dht11_controller (
    input clk,
    input reset,
    input start,

    output reg [15:0] ht,
    output reg [15:0] temp,
    output reg dht11_done,
    output reg dht11_valid,
    // output [3:0] debug,

    inout dhtio  // wire type
);

    wire clk_10us;

    tick_gen_10us U_TICK_10us (
        .clk(clk),
        .reset(reset),
        .clk_10us(clk_10us)
    );

    //state
    parameter IDLE = 3'd0, START = 3'd1, WAIT = 3'd2, SYNC_L = 3'd3, SYNC_H = 3'd4;
    parameter DATA_SYNC = 3'd5, DATA_C = 3'd6, STOP = 3'd7;


    reg [2:0] c_state, n_state;
    reg dhtio_reg, dhtio_next;
    reg io_sel_reg, io_sel_next;
    //18ms count
    reg [10:0] tick_cnt_reg, tick_cnt_next;
    reg [39:0] data_reg, data_next;
    reg [5:0] data_cnt_next, data_cnt_reg;

    reg [16:0] timeout_rst_reg, timeout_rst_next;
    reg [22:0] auto_cnt_reg, auto_cnt_next;

    wire [7:0] data_ht_int = data_reg[39:32];
    wire [7:0] data_ht_dec = data_reg[31:24];
    wire [7:0] data_temp_int = data_reg[23:16];
    wire [7:0] data_temp_dec = data_reg[15:8];
    wire [7:0] data_check_sum = data_reg[7:0];

    wire [7:0] check_valid = data_ht_int + data_ht_dec + data_temp_int + data_temp_dec;

    assign dhtio = (io_sel_reg) ? dhtio_reg : 1'bz; // if io_sel = 0, board circuit open - sensor data drive


    always @(posedge clk, posedge reset) begin
        if (reset) begin
            c_state <= 3'b0;
            dhtio_reg <= 1'b1;
            io_sel_reg <= 1'b1;
            data_reg <= 40'b0;
            data_cnt_reg <= 6'b0;
            tick_cnt_reg <= 11'b0;
            ht <= 16'b0;
            temp <= 16'b0;
            dht11_valid <= 1'b0;
            dht11_done <= 1'b0;
            timeout_rst_reg <= 1'b0;
            auto_cnt_reg <= 23'd6_000_000 - 1;
        end else begin
            c_state <= n_state;
            dhtio_reg <= dhtio_next;
            io_sel_reg <= io_sel_next;
            data_reg <= data_next;
            data_cnt_reg <= data_cnt_next;
            tick_cnt_reg <= tick_cnt_next;
            dht11_done <= 1'b0;
            timeout_rst_reg <= timeout_rst_next;
            auto_cnt_reg <= auto_cnt_next;

            if (c_state == IDLE && n_state == START) begin
                dht11_valid <= 1'b0;
            end

            if (c_state == STOP && n_state == IDLE) begin
                if (check_valid == data_check_sum) begin
                    dht11_valid <= 1'b1;
                    ht <= {data_ht_int, data_ht_dec};
                    temp <= {data_temp_int, data_temp_dec};
                    dht11_done <= 1'b1;
                end else begin
                    dht11_valid <= 1'b0;
                end
            end
        end
    end



    //next output
    always @(*) begin
        n_state    = c_state;
        dhtio_next = dhtio_reg;
        io_sel_next = io_sel_reg;
        tick_cnt_next = tick_cnt_reg;
        data_next = data_reg;
        data_cnt_next = data_cnt_reg;
        timeout_rst_next = timeout_rst_reg;
        auto_cnt_next = auto_cnt_reg;
        if (c_state == IDLE) begin
            timeout_rst_next = 0;
        end else begin
            if (clk_10us) begin
                timeout_rst_next = timeout_rst_reg + 1;
            end
        end

        if (c_state != IDLE && timeout_rst_reg >= 17'd99_999) begin
            n_state = IDLE;
            dhtio_next = 1'b1;
            io_sel_next = 1'b1;
            data_cnt_next = 6'b0;
            tick_cnt_next = 11'b0;

        end else begin
            case (c_state)
                IDLE: begin
                    data_next = 0;
                    tick_cnt_next = 0;
                    data_cnt_next = 0;
                    if (clk_10us) begin
                        if (auto_cnt_reg == 23'd6_000_000 - 1) begin
                            auto_cnt_next = 0;
                            n_state = START;
                        end else begin
                            auto_cnt_next = auto_cnt_reg + 1;
                        end
                    end
                    if (start) begin
                        auto_cnt_next = 0;
                        n_state = START;
                    end
                end
                START: begin
                    dhtio_next = 1'b0;
                    if (clk_10us) begin
                        tick_cnt_next = tick_cnt_reg + 1;
                        if (tick_cnt_reg == 1900) begin
                            tick_cnt_next = 0;
                            n_state = WAIT;
                        end
                    end
                end
                WAIT: begin
                    dhtio_next = 1'b1;
                    if (clk_10us) begin
                        tick_cnt_next = tick_cnt_reg + 1;
                        if (tick_cnt_reg == 3) begin
                            //for output to high-z
                            n_state = SYNC_L;
                            io_sel_next = 1'b0;
                        end
                    end
                end
                SYNC_L: begin
                    if (clk_10us) begin
                        if (dhtio == 1) begin
                            n_state = SYNC_H;
                        end
                    end
                end
                SYNC_H: begin
                    if (clk_10us) begin
                        if (dhtio == 0) begin
                            n_state = DATA_SYNC;
                        end
                    end
                end
                DATA_SYNC: begin
                    if (clk_10us) begin
                        if (dhtio == 1) begin
                            tick_cnt_next = 0;
                            n_state = DATA_C;
                        end
                    end
                end
                DATA_C: begin
                    if (clk_10us) begin
                        if (dhtio == 1) begin
                            tick_cnt_next = tick_cnt_reg + 1;
                        end else begin
                            if (tick_cnt_reg >= 5) begin
                                data_next = {data_reg[38:0], 1'b1};
                            end else begin
                                data_next = {data_reg[38:0], 1'b0};
                            end
                            if (data_cnt_reg == 39) begin
                                tick_cnt_next = 0;
                                n_state = STOP;
                            end else begin
                                data_cnt_next = data_cnt_reg + 1;
                                n_state = DATA_SYNC;
                            end
                        end
                    end
                end
                STOP: begin
                    if (clk_10us) begin
                        tick_cnt_next = tick_cnt_reg + 1;
                        if (tick_cnt_reg == 5) begin  //need 50us to stop
                            //output mode
                            io_sel_next = 1'b1;
                            dhtio_next = 1'b1;
                            n_state = IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule


//=================
//  tick gen 10usec
//=================
module tick_gen_10us (
    input clk,
    input reset,
    output reg clk_10us
);
    reg [9:0] count_reg;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            count_reg <= 0;
            clk_10us  <= 1'b0;
        end else if (count_reg == 999) begin
            count_reg <= 0;
            clk_10us  <= 1'b1;
        end else begin
            count_reg <= count_reg + 1;
            clk_10us  <= 1'b0;
        end
    end
endmodule
