
// systolic_array_4x4.v  -  4x4 grid of PEs (output stationary)
//
//            b_edge[0] b_edge[1] b_edge[2] b_edge[3]
//                |         |         |         |
//  a_edge[0] -> PE00 ---> PE01 ---> PE02 ---> PE03
//                |         |         |         |
//  a_edge[1] -> PE10 ---> PE11 ---> PE12 ---> PE13
//                |         |         |         |
//  a_edge[2] -> PE20 ---> PE21 ---> PE22 ---> PE23
//                |         |         |         |
//  a_edge[3] -> PE30 ---> PE31 ---> PE32 ---> PE33
//
// Inputs are flattened buses (Verilog-2001 friendly):
//   a_edge_flat[8*i +: 8] = value entering row i from the left
//   b_edge_flat[8*j +: 8] = value entering column j from the top
//   c_flat[32*(4*i+j) +: 32] = C[i][j]

module systolic_array_4x4 #(
    parameter N   = 4,
    parameter DW  = 8,
    parameter ACW = 32
)(
    input  wire                 clk,
    input  wire                 clr,
    input  wire [N*DW-1:0]      a_edge_flat,
    input  wire [N*DW-1:0]      b_edge_flat,
    output wire [N*N*ACW-1:0]   c_flat
);
    // Horizontal wires: a_h[i][j] feeds PE(i,j); a_h[i][N] is unused output
    wire signed [DW-1:0] a_h [0:N-1][0:N];
    // Vertical wires:   b_v[i][j] feeds PE(i,j); b_v[N][j] is unused output
    wire signed [DW-1:0] b_v [0:N][0:N-1];

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_left
            assign a_h[i][0] = a_edge_flat[DW*i +: DW];
        end
        for (j = 0; j < N; j = j + 1) begin : g_top
            assign b_v[0][j] = b_edge_flat[DW*j +: DW];
        end

        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                wire signed [ACW-1:0] acc_w;
                pe #(.DW(DW), .ACW(ACW)) u_pe (
                    .clk  (clk),
                    .clr  (clr),
                    .a_in (a_h[i][j]),
                    .b_in (b_v[i][j]),
                    .a_out(a_h[i][j+1]),
                    .b_out(b_v[i+1][j]),
                    .acc  (acc_w)
                );
                assign c_flat[ACW*(N*i+j) +: ACW] = acc_w;
            end
        end
    endgenerate
endmodule
