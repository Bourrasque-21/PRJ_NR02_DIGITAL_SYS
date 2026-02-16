`timescale 1ns / 1ps

module uart_top (
    input  wire clk,
    input  wire reset,
    input  wire uart_rx,
    output wire uart_tx,

    output wire       o_btn_r,
    output wire       o_btn_n,
    output wire       o_btn_c,
    output wire       o_btn_sr,
    output wire       o_btn_dht,
    output reg        pc_ctrl_mode,
    output reg  [4:0] pc_mode_sw,

    input wire [23:0] clock_time24,
    input wire [15:0] dht11_temp_data,
    input wire [15:0] dht_ht_data
);

    wire       b_tick;
    wire       rx_done;
    wire [7:0] rx_data;

    wire [7:0] w_tx_fifo_pop_data;
    wire       w_tx_fifo_full;
    wire       w_tx_fifo_empty;
    wire       w_tx_busy;
    wire       w_uart_tx_done;

    wire       w_time_tx_start;
    wire [7:0] w_time_tx_data;

    wire       w_tx_start = (~w_tx_busy) & (~w_tx_fifo_empty);
    wire       w_tx_push = w_time_tx_start & (~w_tx_fifo_full);

    wire       q = rx_done && (rx_data == 8'h51); // 'Q'

    wire [4:0] hour = clock_time24[23:19];
    wire [5:0] min = clock_time24[18:13];
    wire [5:0] sec = clock_time24[12:7];
    wire [6:0] cc = clock_time24[6:0];
    wire [7:0] temp_int = dht11_temp_data[15:8];
    wire [7:0] ht_int = dht_ht_data[15:8];

    uart_tx U_UART_TX (
        .clk     (clk),
        .reset   (reset),
        .tx_start(w_tx_start),
        .b_tick  (b_tick),
        .tx_data (w_tx_fifo_pop_data),
        .tx_busy (w_tx_busy),
        .tx_done (w_uart_tx_done),
        .uart_tx (uart_tx)
    );

    fifo U_FIFO_TX (
        .clk      (clk),
        .rst      (reset),
        .push     (w_tx_push),
        .pop      (w_tx_start),
        .push_data(w_time_tx_data),
        .pop_data (w_tx_fifo_pop_data),
        .full     (w_tx_fifo_full),
        .empty    (w_tx_fifo_empty)
    );

    uart_rx U_UART_RX (
        .clk    (clk),
        .reset  (reset),
        .rx     (uart_rx),
        .b_tick (b_tick),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    baud_tick U_BAUD_TICK (
        .clk   (clk),
        .reset (reset),
        .b_tick(b_tick)
    );

    ascii_decoder U_ASCII_DECODER (
        .clk       (clk),
        .reset     (reset),
        .rx_data   (rx_data),
        .rx_done   (rx_done),
        .in_btn_r  (o_btn_r),
        .in_btn_n  (o_btn_n),
        .in_btn_c  (o_btn_c),
        .in_btn_sr (o_btn_sr),
        .in_btn_dht(o_btn_dht)
    );

    uart_time_sender U_TIME_SENDER (
        .clk     (clk),
        .reset   (reset),
        .start   (q),
        .tx_done (w_uart_tx_done),
        .tx_start(w_time_tx_start),
        .tx_data (w_time_tx_data),
        .hour    (hour),
        .min     (min),
        .sec     (sec),
        .cc      (cc),
        .temp_int(temp_int),
        .ht_int  (ht_int)
    );

    // PC mode
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_ctrl_mode <= 1'b0;
            pc_mode_sw   <= 5'b00000;
        end else if (rx_done) begin
            case (rx_data)
                8'h4D:   pc_ctrl_mode <= ~pc_ctrl_mode;   // 'M'  
                8'h30:   pc_mode_sw[0] <= ~pc_mode_sw[0]; // '0'
                8'h31:   pc_mode_sw[1] <= ~pc_mode_sw[1]; // '1'
                8'h32:   pc_mode_sw[2] <= ~pc_mode_sw[2]; // '2'
                8'h33:   pc_mode_sw[3] <= ~pc_mode_sw[3]; // '3'
                8'h34:   pc_mode_sw[4] <= ~pc_mode_sw[4]; // '4'
                default: ;
            endcase
        end
    end
endmodule


module uart_rx (
    input  wire       clk,
    input  wire       reset,
    input  wire       rx,
    input  wire       b_tick,
    output wire [7:0] rx_data,
    output wire       rx_done
);
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] c_state, n_state;
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    reg done_reg, done_next;
    reg [7:0] buf_reg, buf_next;

    assign rx_data = buf_reg;
    assign rx_done = done_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            c_state        <= IDLE;
            b_tick_cnt_reg <= 4'd0;
            bit_cnt_reg    <= 3'd0;
            done_reg       <= 1'b0;
            buf_reg        <= 8'd0;
        end else begin
            c_state        <= n_state;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            done_reg       <= done_next;
            buf_reg        <= buf_next;
        end
    end

    always @(*) begin
        n_state         = c_state;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        done_next       = 1'b0;
        buf_next        = buf_reg;

        case (c_state)
            IDLE: begin
                b_tick_cnt_next = 4'd0;
                bit_cnt_next    = 3'd0;

                if (b_tick && !rx) begin
                    buf_next = 8'd0;
                    n_state  = START;
                end
            end

            START: begin

                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd7) begin
                        b_tick_cnt_next = 4'd0;
                        n_state         = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1'b1;
                    end
                end
            end

            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd15) begin
                        b_tick_cnt_next = 4'd0;

                        buf_next = {rx, buf_reg[7:1]};

                        if (bit_cnt_reg == 3'd7) begin
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1'b1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1'b1;
                    end
                end
            end

            STOP: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd15) begin
                        n_state   = IDLE;
                        done_next = 1'b1;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1'b1;
                    end
                end
            end

            default: begin
                n_state = IDLE;
            end
        endcase
    end
endmodule


module uart_tx (
    input  wire       clk,
    input  wire       reset,
    input  wire       tx_start,
    input  wire       b_tick,
    input  wire [7:0] tx_data,
    output wire       tx_busy,
    output wire       tx_done,
    output wire       uart_tx
);
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] current_state, next_state;

    reg tx_reg, tx_next;
    reg [2:0] bit_cnt_reg, bit_cnt_next;
    reg [3:0] b_tick_cnt_reg, b_tick_cnt_next;

    reg busy_reg, busy_next;
    reg done_reg, done_next;

    reg [7:0] data_in_buf_reg, data_in_buf_next;

    assign uart_tx = tx_reg;
    assign tx_busy = busy_reg;
    assign tx_done = done_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state   <= IDLE;
            tx_reg          <= 1'b1;
            bit_cnt_reg     <= 3'd0;
            b_tick_cnt_reg  <= 4'd0;
            busy_reg        <= 1'b0;
            done_reg        <= 1'b0;
            data_in_buf_reg <= 8'h00;
        end else begin
            current_state   <= next_state;
            tx_reg          <= tx_next;
            bit_cnt_reg     <= bit_cnt_next;
            b_tick_cnt_reg  <= b_tick_cnt_next;
            busy_reg        <= busy_next;
            done_reg        <= done_next;
            data_in_buf_reg <= data_in_buf_next;
        end
    end

    always @(*) begin
        next_state       = current_state;
        tx_next          = tx_reg;
        bit_cnt_next     = bit_cnt_reg;
        b_tick_cnt_next  = b_tick_cnt_reg;
        busy_next        = busy_reg;
        done_next        = 1'b0;
        data_in_buf_next = data_in_buf_reg;

        case (current_state)
            IDLE: begin
                tx_next         = 1'b1;
                busy_next       = 1'b0;
                bit_cnt_next    = 3'd0;
                b_tick_cnt_next = 4'd0;

                if (tx_start) begin
                    busy_next        = 1'b1;
                    data_in_buf_next = tx_data;
                    next_state       = START;
                end
            end

            START: begin
                tx_next = 1'b0;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd15) begin
                        b_tick_cnt_next = 4'd0;
                        next_state      = DATA;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1'b1;
                    end
                end
            end

            DATA: begin
                tx_next = data_in_buf_reg[0];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd15) begin
                        b_tick_cnt_next = 4'd0;

                        if (bit_cnt_reg == 3'd7) begin
                            next_state = STOP;
                        end else begin
                            bit_cnt_next     = bit_cnt_reg + 1'b1;
                            data_in_buf_next = {1'b0, data_in_buf_reg[7:1]};
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1'b1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd15) begin
                        next_state = IDLE;
                        done_next  = 1'b1;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1'b1;
                    end
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end
endmodule

module baud_tick (
    input  wire clk,
    input  wire reset,
    output reg  b_tick
);
    parameter BAUDRATE = 9600 * 16;
    parameter F_COUNT = 100_000_000 / BAUDRATE;

    reg [$clog2(F_COUNT)-1:0] counter_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            b_tick      <= 1'b0;
            counter_reg <= 0;
        end else begin
            counter_reg <= counter_reg + 1'b1;

            if (counter_reg == (F_COUNT - 1)) begin
                counter_reg <= 0;
                b_tick      <= 1'b1;
            end else begin
                b_tick <= 1'b0;
            end
        end
    end
endmodule


//=============================================================
// ASCII Decoder
//=============================================================
module ascii_decoder (
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] rx_data,
    input  wire       rx_done,
    output reg        in_btn_r,
    output reg        in_btn_n,
    output reg        in_btn_c,
    output reg        in_btn_sr,
    output reg        in_btn_dht
);
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            in_btn_r   <= 1'b0;
            in_btn_n   <= 1'b0;
            in_btn_c   <= 1'b0;
            in_btn_sr  <= 1'b0;
            in_btn_dht <= 1'b0;
        end else begin
            in_btn_r   <= 1'b0;
            in_btn_n   <= 1'b0;
            in_btn_c   <= 1'b0;
            in_btn_sr  <= 1'b0;
            in_btn_dht <= 1'b0;

            if (rx_done) begin
                case (rx_data)
                    8'h52:   in_btn_r <= 1'b1;
                    8'h4E:   in_btn_n <= 1'b1;
                    8'h43:   in_btn_c <= 1'b1;
                    8'h54:   in_btn_sr <= 1'b1;
                    8'h48:   in_btn_dht <= 1'b1;
                    default: ;
                endcase
            end
        end
    end
endmodule


//=============================================================
// ASCII Sender
//=============================================================
module uart_time_sender (
    input wire clk,
    input wire reset,
    input wire start,
    input wire tx_done,

    output reg       tx_start,
    output reg [7:0] tx_data,

    input wire [4:0] hour,
    input wire [5:0] min,
    input wire [5:0] sec,
    input wire [6:0] cc,

    input wire [7:0] temp_int,
    // input wire [7:0] temp_dec,
    input wire [7:0] ht_int
    // input wire [7:0] ht_dec
);

    wire [3:0] h1 = hour % 10;
    wire [3:0] h10 = hour / 10;
    wire [3:0] m1 = min % 10;
    wire [3:0] m10 = min / 10;
    wire [3:0] s1 = sec % 10;
    wire [3:0] s10 = sec / 10;
    wire [3:0] c1 = cc % 10;
    wire [3:0] c10 = cc / 10;

    wire [3:0] temp1 = temp_int % 10;
    wire [3:0] temp10 = temp_int / 10;
    wire [3:0] ht1 = ht_int % 10;
    wire [3:0] ht10 = ht_int / 10;

    reg [7:0] msg[0:30];
    
    always @(*) begin
        msg[0]  = 8'h30 + h10; // H
        msg[1]  = 8'h30 + h1;  // H
        msg[2]  = 8'h3A;       // :
        msg[3]  = 8'h30 + m10; // M  
        msg[4]  = 8'h30 + m1;  // M
        msg[5]  = 8'h3A;       // :
        msg[6]  = 8'h30 + s10; // S 
        msg[7]  = 8'h30 + s1;  // S 
        msg[8]  = 8'h3A;       // :
        msg[9]  = 8'h30 + c10; // C 
        msg[10] = 8'h30 + c1;  // C 
        msg[11] = 8'h0D;       // \r
        msg[12] = 8'h0A;       // \n

        msg[13] = 8'h54;          // T
        msg[14] = 8'h20;          // 
        msg[15] = 8'h30 + temp10; // X    
        msg[16] = 8'h30 + temp1;  // X    
        msg[17] = 8'h2E;          // .
        msg[18] = 8'h30;          // X
        msg[19] = 8'h43;          // C
        msg[20] = 8'h0D;          // \r
        msg[21] = 8'h0A;          // \n 

        msg[22] = 8'h48;          // H
        msg[23] = 8'h20;          // 
        msg[24] = 8'h30 + ht10;   // X    
        msg[25] = 8'h30 + ht1;    // X    
        msg[26] = 8'h2E;          // .
        msg[27] = 8'h30;          // X
        msg[28] = 8'h25;          // %
        msg[29] = 8'h0D;          // \r
        msg[30] = 8'h0A;          // \n 
    end

    localparam S_IDLE = 2'd0;
    localparam S_SEND = 2'd1;
    localparam S_WAIT = 2'd2;

    reg [1:0] state, state_n;
    reg [4:0] idx, idx_n;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            idx   <= 5'd0;
        end else begin
            state <= state_n;
            idx   <= idx_n;
        end
    end

    always @(*) begin
        state_n  = state;
        idx_n    = idx;
        tx_start = 1'b0;
        tx_data  = 8'h00;

        case (state)
            S_IDLE: begin
                if (start) begin
                    idx_n   = 5'd0;
                    state_n = S_SEND;
                end
            end

            S_SEND: begin
                tx_data  = msg[idx];
                tx_start = 1'b1;
                state_n  = S_WAIT;
            end

            S_WAIT: begin
                if (tx_done) begin
                    if (idx == 5'd30) state_n = S_IDLE;
                    else begin
                        idx_n   = idx + 1'b1;
                        state_n = S_SEND;
                    end
                end
            end

            default: state_n = S_IDLE;
        endcase
    end

endmodule


