
// pe.v  -  Processing Element for an output-stationary systolic array
//
//   a_in --->[ MAC ]---> a_out      (A values move left -> right)
//              |
//   b_in  (from top)                (B values move top -> bottom)
//              v
//            b_out
//
// Every clock:  acc   <= acc + a_in * b_in
//               a_out <= a_in       (pass to right neighbour)
//               b_out <= b_in       (pass to bottom neighbour)
// The result C[i][j] stays inside this PE ("output stationary").

module pe #(
    parameter DW  = 8,     // operand width (signed INT8)
    parameter ACW = 32     // accumulator width
)(
    input  wire                  clk,
    input  wire                  clr,     // synchronous clear of acc + pipeline
    input  wire signed [DW-1:0]  a_in,
    input  wire signed [DW-1:0]  b_in,
    output reg  signed [DW-1:0]  a_out,
    output reg  signed [DW-1:0]  b_out,
    output reg  signed [ACW-1:0] acc
);
    wire signed [2*DW-1:0] prod = a_in * b_in;   // maps to a DSP48 / LUT multiplier

    always @(posedge clk) begin
        if (clr) begin
            acc   <= {ACW{1'b0}};
            a_out <= {DW{1'b0}};
            b_out <= {DW{1'b0}};
        end else begin
            acc   <= acc + {{(ACW-2*DW){prod[2*DW-1]}}, prod};  // sign-extend
            a_out <= a_in;
            b_out <= b_in;
        end
    end
endmodule
