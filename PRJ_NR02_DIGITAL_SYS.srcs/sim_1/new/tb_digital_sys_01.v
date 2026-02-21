`timescale 1ns / 1ps

module TEST_sys ();

    parameter BAUD = 9600;
    parameter BAUD_PERIOD = (100_000_000 / BAUD) * 10;

    reg clk;
    reg reset;
    reg [4:0] mode_sw;
    reg btn_8;
    reg btn_5;
    reg btn_2;
    reg sr04_start;
    reg dht11_btn_start;
    reg uart_rx;
    reg echo;

    wire trig;
    wire uart_tx;
    wire [3:0] fnd_digit;
    wire [7:0] fnd_data;
    wire [3:0] out_led;
    wire pc_mode_led;
    wire valid_led;

    wire dhtio;
    reg [7:0] test_data;  // UART SEND DATA
    reg [39:0] dht11_sensor_data;  // DHT11 TEST DATA
    reg dht11_sensor_io, sensor_io_sel;
    reg [39:0] dht11_data_reg;

    assign dhtio = (sensor_io_sel) ? 1'bz : dht11_sensor_io;
    pullup (dhtio);

    integer i;

    top_stopwatch_watch dut (
        .reset(reset),
        .clk(clk),
        .mode_sw(mode_sw),
        .btn_8(btn_8),
        .btn_5(btn_5),
        .btn_2(btn_2),
        .sr04_start(sr04_start),
        .dht11_btn_start(dht11_btn_start),
        .uart_rx(uart_rx),
        .echo(echo),
        .dhtio(dhtio),

        .trig(trig),
        .uart_tx(uart_tx),
        .fnd_digit(fnd_digit),
        .fnd_data(fnd_data),
        .out_led(out_led),
        .pc_mode_led(pc_mode_led),
        .dht11_valid(valid_led)
    );

    always #5 clk = ~clk;

task dht11_ctrl();
    integer k;
    begin
        sensor_io_sel   = 1'b0;
        // response 80us low / 80us high
        dht11_sensor_io = 1'b0; #80_000;
        dht11_sensor_io = 1'b1; #80_000;

        for (k = 39; k >= 0; k = k - 1) begin
            dht11_sensor_io = 1'b0; #60_000;  
            dht11_sensor_io = 1'b1;
            if (dht11_sensor_data[k] == 0) #30_000; 
            else                           #80_000; 
        end
        dht11_sensor_io = 1'b0; 
        #50_000;   
        // release
        sensor_io_sel   = 1'b1;
        dht11_sensor_io = 1'b1;
    end
endtask

task dht11_ctrl_error();
    integer k;
    begin
        sensor_io_sel   = 1'b0;
        // response 80us low / 80us high
        dht11_sensor_io = 1'b0; #80_000;
        dht11_sensor_io = 1'b1; #80_000;

        for (k = 3; k >= 0; k = k - 1) begin
            dht11_sensor_io = 1'b0; #60_000;  
            dht11_sensor_io = 1'b1;
            if (dht11_sensor_data[k] == 0) #30_000; 
            else                           #80_000; 
        end
        // dht11_sensor_io = 1'b0; 
        // #50_000;   
        // // release
        // sensor_io_sel   = 1'b1;
        // dht11_sensor_io = 1'b1;
    end
endtask

    //UART PC input control
    task uart_sender();
        begin
            //start
            uart_rx = 0;
            #(BAUD_PERIOD);
            //data
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = test_data[i];
                #(BAUD_PERIOD);
            end
            //stop
            uart_rx = 1'b1;
            #(BAUD_PERIOD);
        end
    endtask

    task press_btn_8();
        begin
            btn_8 = 1'b1;
            #100_000;
            btn_8 = 1'b0;
        end
    endtask

    task press_btn_5();
        begin
            btn_5 = 1'b1;
            #100_000;
            btn_5 = 1'b0;
        end
    endtask

    task press_btn_2();
        begin
            btn_2 = 1'b1;
            #100_000;
            btn_2 = 1'b0;
        end
    endtask

    task press_btn_sr04();
        begin
            sr04_start = 1'b1;
            #100_000;
            sr04_start = 1'b0;
        end
    endtask

    task press_btn_dht11();
        begin
            dht11_btn_start = 1'b1;
            #100_000;
            dht11_btn_start = 1'b0;
        end
    endtask


    //
    // SW = [a] [] [] [b] []
    //      a, b = mode sw
    initial begin
        #0;
        reset = 1;
        clk = 1;
        mode_sw = 5'b01010;
        btn_2 = 0;
        btn_5 = 0;
        btn_8 = 0;
        sr04_start = 0;
        dht11_btn_start = 0;
        uart_rx = 1;
        echo = 0;
        dht11_sensor_io = 1'b1;
        sensor_io_sel = 1'b1;

        dht11_sensor_data = {8'h32, 8'h00, 8'h19, 8'h00, 8'h4b};
        // 0011 0010 / / 0001 1001 / 0100 1011 // T = 25, H = 50

        //==========================================
        // 0. Stopwatch/Clock - Time-set (25:01:00.00)
        //==========================================
        #100;
        reset = 0;
        #10000;
        press_btn_5();
        #10000;
        press_btn_5();
        #10000;
        press_btn_8();
        #10000;
        press_btn_dht11();
        #10000;
        press_btn_5();
        #10000;
        press_btn_sr04();
        #10000;
        press_btn_2();
        #10000;
        mode_sw = 5'b00000;
        //==========================================
        //==========================================
        // 1. SW & Btn Command Test
        //==========================================

        #(BAUD_PERIOD * 250);test_data = 8'h52;  // btn 8
        uart_sender();
        #(BAUD_PERIOD * 250);

        mode_sw = 5'b00010;       
        #(BAUD_PERIOD * 200);
        mode_sw = 5'b00001;
        #(BAUD_PERIOD * 200);
        mode_sw = 5'b00011;
        #(BAUD_PERIOD * 200);


        test_data = 8'h4D;       // pc_ctrl_mode M
        uart_sender();
        #(BAUD_PERIOD * 200);

        //

        wait (dut.U_DHT11_UNIT.U_DHT11.io_sel_reg == 1'b0);
        #1000;

        dht11_ctrl(); // dht11 AUTO start

        //test_data = 8'h32;     //sw2
        //uart_sender();
        #(BAUD_PERIOD * 200);

        mode_sw = 5'b01010;       
        #(BAUD_PERIOD * 200);
        mode_sw = 5'b00101;       
        #(BAUD_PERIOD * 200);
        mode_sw = 5'b00000;
        #(BAUD_PERIOD * 200);

        test_data = 8'h31; //sw1
        uart_sender();
        #(BAUD_PERIOD * 250);

        test_data = 8'h33; //sw3
        uart_sender();
        #(BAUD_PERIOD * 250);


        btn_5 = 1'b1;
        #(5_000_000);           
        btn_5 = 1'b0;
        #(BAUD_PERIOD * 250);


        test_data = 8'h4E;  //btn 5
        uart_sender();
        #(BAUD_PERIOD * 250);


        test_data = 8'h4E;  //btn 5
        uart_sender();
        #(5_000_000);
        #(BAUD_PERIOD * 250);


        btn_8 = 1'b1; #(5_000_000); btn_8 = 1'b0; #(BAUD_PERIOD * 200);

        test_data = 8'h43; // btn 2
        uart_sender();

        #(BAUD_PERIOD * 250);test_data = 8'h52; //btn 8
        uart_sender();
        #(BAUD_PERIOD * 250);


        btn_2 = 1'b1; #(5_000_000); btn_2 = 1'b0; #(BAUD_PERIOD * 250);


        test_data = 8'h33;       // sw 3
        uart_sender();
        #(BAUD_PERIOD * 250);

        test_data = 8'h4D;     // PC mode off M
        uart_sender();
        #(BAUD_PERIOD * 250);

        mode_sw = 5'b00010;
        #(BAUD_PERIOD * 200);
        mode_sw = 5'b10010;
        #(BAUD_PERIOD * 200);
        dht11_sensor_data = {8'h28, 8'h00, 8'h1b, 8'h00, 8'h43}; // T = 27, H = 40
        #(BAUD_PERIOD * 200);
        press_btn_dht11();
        #(BAUD_PERIOD * 200);
        dht11_ctrl();
        #(BAUD_PERIOD * 200);
        mode_sw = 5'b10000;

        //==========================================
        // 3.1 Sr04 - General (Dist., trig, Sync, edge trig)
        //==========================================
        press_btn_sr04();
        #10_000;
        echo = 1;
        #580_000;
        echo = 0;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        //==========================================
        // 3.2 Sr04 - Time-out case.1 (TRIG timeout)
        //==========================================
        press_btn_sr04();
        #30_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);    
        #10_000_000;

        press_btn_sr04();
        #10_000;
        echo = 1;
        #720_000;
        echo = 0;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;

        //==========================================
        // 3.2 Sr04 - Time-out case.2 (Echo timeout)
        //==========================================
        press_btn_sr04();
        #10_000;
        echo = 1;
        #30_000_000;
        echo = 0;


        //==========================================
        // 4. DHT11 module - general (Auto Start)
        //==========================================

        //==========================================





        //==========================================
        // 4.ASCII Sender
        //==========================================
        test_data = 8'h51; // Q
        uart_sender();


        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        #10_000_000;
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        mode_sw = 5'b10010;
        #10_000_000;
        
        press_btn_dht11();
        #(BAUD_PERIOD);
        #(BAUD_PERIOD);
        dht11_ctrl_error();

        $stop;
    end




endmodule

