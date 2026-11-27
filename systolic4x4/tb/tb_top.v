`timescale 1ns/1ps
module tb_top;
    localparam CPB    = 16;          // clocks per UART bit in simulation
    localparam CLK_NS = 10;          // 100 MHz
    localparam BIT_NS = CPB*CLK_NS;
    localparam NTESTS = 20;

    reg  clk = 0, btnC = 1, RsRx = 1;
    wire RsTx;
    wire [15:0] led;

    always #(CLK_NS/2) clk = ~clk;

    top #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(100000)) dut (
        .clk(clk), .btnC(btnC), .RsRx(RsRx), .RsTx(RsTx), .led(led));

    //  PC-side UART helpers 
    task send_byte(input [7:0] b);
        integer k;
        begin
            RsRx = 0; #(BIT_NS);                     // start bit
            for (k = 0; k < 8; k = k + 1) begin
                RsRx = b[k]; #(BIT_NS);              // LSB first
            end
            RsRx = 1; #(BIT_NS);                     // stop bit
        end
    endtask

    task recv_byte(output [7:0] b);
        integer k;
        begin
            @(negedge RsTx);                         // start bit edge
            #(BIT_NS + BIT_NS/2);                    // centre of bit 0
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = RsTx; #(BIT_NS);
            end
        end
    endtask

    // test data 
    reg signed [7:0]  A [0:3][0:3];
    reg signed [7:0]  B [0:3][0:3];
    reg signed [31:0] exp_c, got_c;
    reg [7:0] rb;
    integer t, i, j, k, errors, total_errors;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        total_errors = 0;

        #(20*CLK_NS) btnC = 0;
        #(20*CLK_NS);

        for (t = 0; t < NTESTS; t = t + 1) begin
            // Test 0: corner case (all -128) -> max magnitude result 65536
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1) begin
                    A[i][j] = (t == 0) ? -8'sd128 : $random;
                    B[i][j] = (t == 0) ? -8'sd128 : $random;
                end

            // send A then B, row-major
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1) send_byte(A[i][j]);
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1) send_byte(B[i][j]);

            // receive and check 16 results
            errors = 0;
            for (i = 0; i < 4; i = i + 1)
                for (j = 0; j < 4; j = j + 1) begin
                    got_c = 0;
                    for (k = 0; k < 4; k = k + 1) begin
                        recv_byte(rb);
                        got_c = {got_c[23:0], rb};   // MSB first
                    end
                    exp_c = 0;
                    for (k = 0; k < 4; k = k + 1)
                        exp_c = exp_c + A[i][k] * B[k][j];
                    if (got_c !== exp_c) begin
                        errors = errors + 1;
                        $display("  MISMATCH test %0d C[%0d][%0d]: got %0d exp %0d",
                                 t, i, j, got_c, exp_c);
                    end
                end
            total_errors = total_errors + errors;
            $display("Test %0d : %s", t, errors ? "FAIL" : "PASS");
        end

        if (total_errors == 0)
            $display("ALL %0d TESTS PASSED  (jobs counter on LEDs = %0d)", NTESTS, led[15:8]);
        else
            $display("FAILED with %0d mismatches", total_errors);
        $finish;
    end
endmodule
