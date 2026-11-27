`timescale 1ns/1ps
module tb_array;
    localparam N = 8;
    reg clk = 0, clr = 1;
    reg  [8*N-1:0]      a_edge_flat = 0, b_edge_flat = 0;
    wire [32*N*N-1:0]   c_flat;
    always #5 clk = ~clk;

    systolic_array_8x8 #(.N(N)) dut (.clk(clk), .clr(clr),
        .a_edge_flat(a_edge_flat), .b_edge_flat(b_edge_flat), .c_flat(c_flat));

    reg signed [7:0]  A [0:N-1][0:N-1];
    reg signed [7:0]  B [0:N-1][0:N-1];
    reg signed [31:0] exp_c, got_c;
    integer t, i, j, k, errors = 0;

    initial begin
        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                A[i][j] = N*i + j + 1;      // 1..64
                B[i][j] = (i == j) ? 2 : 0; // 2*I  -> C = 2A
            end

        @(posedge clk); @(posedge clk);
        clr <= 0;

        for (t = 0; t < 3*N; t = t + 1) begin
            for (i = 0; i < N; i = i + 1) begin
                a_edge_flat[8*i +: 8] <= (t >= i && t < i+N) ? A[i][t-i] : 8'd0;
                b_edge_flat[8*i +: 8] <= (t >= i && t < i+N) ? B[t-i][i] : 8'd0;
            end
            @(posedge clk);
        end
        a_edge_flat <= 0; b_edge_flat <= 0;
        repeat (4) @(posedge clk);

        for (i = 0; i < N; i = i + 1)
            for (j = 0; j < N; j = j + 1) begin
                got_c = c_flat[32*(N*i+j) +: 32];
                exp_c = 0;
                for (k = 0; k < N; k = k + 1) exp_c = exp_c + A[i][k]*B[k][j];
                if (got_c !== exp_c) begin
                    errors = errors + 1;
                    $display("C[%0d][%0d] got %0d exp %0d", i, j, got_c, exp_c);
                end
            end
        $display(errors ? "ARRAY TEST FAILED" : "ARRAY TEST PASSED");
        $finish;
    end
endmodule
