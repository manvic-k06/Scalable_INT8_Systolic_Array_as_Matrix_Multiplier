
// top.v  -  UART-connected 8x8 INT8 systolic-array matrix multiplier
// Protocol (host -> FPGA): 128 bytes
//      bytes   0..63  : A (row-major, signed INT8)   A[i][k] = byte[8*i + k]
//      bytes  64..127 : B (row-major, signed INT8)   B[k][j] = byte[64 + 8*k + j]
// Protocol (FPGA -> host): 256 bytes
//      C = A x B, 64 signed 32-bit results, row-major, each MSB first
//
// FSM:  RX (collect 128 bytes) -> CLR -> RUN (28 cycles) -> TX (256 bytes) -> RX
//
// Board: Digilent Basys 3 (100 MHz).  LEDs:
//      led[0]  = waiting for data     led[1] = computing
//      led[2]  = transmitting         led[15:8] = number of jobs completed

module top #(
    parameter CLKS_PER_BIT = 868,          // 100 MHz / 115200 baud
    parameter TIMEOUT_CLKS = 10_000_000    // 0.1 s: drop a half-received frame
)(
    input  wire        clk,                // 100 MHz
    input  wire        btnC,               // reset (active high)
    input  wire        RsRx,               // UART from PC
    output wire        RsTx,               // UART to PC
    output wire [15:0] led
);
    localparam N = 8, DW = 8, ACW = 32;
    localparam NIN  = 2*N*N;               // 128 bytes received (A then B)
    localparam NOUT = 4*N*N;               // 256 bytes sent (64 results x 4 bytes)

    
    // Reset synchronizer
    reg rst_m, rst;
    always @(posedge clk) begin
        rst_m <= btnC;
        rst   <= rst_m;
    end

    // UART
    wire       rx_dv;
    wire [7:0] rx_byte;
    reg        tx_dv;
    reg  [7:0] tx_byte;
    wire       tx_busy, tx_done;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .i_rx(RsRx), .o_dv(rx_dv), .o_byte(rx_byte));

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .i_dv(tx_dv), .i_byte(tx_byte),
        .o_tx(RsTx), .o_busy(tx_busy), .o_done(tx_done));


    // Operand storage: mat[0..63] = A, mat[64..127] = B
    reg signed [7:0] mat [0:NIN-1];

    
    // Systolic array
    reg                  arr_clr;
    reg  [N*DW-1:0]      a_edge_flat, b_edge_flat;
    wire [N*N*ACW-1:0]   c_flat;
    reg  [N*N*ACW-1:0]   c_reg;

    systolic_array_8x8 #(.N(N), .DW(DW), .ACW(ACW)) u_array (
        .clk(clk), .clr(arr_clr),
        .a_edge_flat(a_edge_flat), .b_edge_flat(b_edge_flat),
        .c_flat(c_flat));


    // Control FSM
    localparam S_RX      = 3'd0,
               S_CLR     = 3'd1,
               S_RUN     = 3'd2,
               S_TX_LOAD = 3'd3,
               S_TX_WAIT = 3'd4;

    // Last product is added at RUN edge 3N-2 = 22, and c_reg is copied at edge
    // RUN_CYCLES-1, so RUN_CYCLES >= 3N = 24 is required (cycle-accurate model).
    // 3N+4 = 28 keeps the same margin as the 4x4 design (16 = 3*4+4).
    localparam RUN_CYCLES = 3*N + 4;

    reg [2:0]  state;
    reg [6:0]  rx_cnt;        // 0..127
    reg [4:0]  t;             // compute time step, 0..28
    reg [7:0]  tx_cnt;        // 0..255
    reg [7:0]  jobs;
    reg [23:0] idle_cnt;

    integer i;

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_RX;
            rx_cnt      <= 0;
            t           <= 0;
            tx_cnt      <= 0;
            jobs        <= 0;
            idle_cnt    <= 0;
            arr_clr     <= 1'b1;
            tx_dv       <= 1'b0;
            tx_byte     <= 8'd0;
            a_edge_flat <= 0;
            b_edge_flat <= 0;
            c_reg       <= 0;
        end else begin
            arr_clr <= 1'b0;
            tx_dv   <= 1'b0;

            case (state)
                //  receive 128 operand bytes 
                S_RX: begin
                    a_edge_flat <= 0;
                    b_edge_flat <= 0;
                    if (rx_dv) begin
                        mat[rx_cnt] <= rx_byte;
                        idle_cnt    <= 0;
                        if (rx_cnt == NIN-1) begin
                            rx_cnt <= 0;
                            state  <= S_CLR;
                        end else
                            rx_cnt <= rx_cnt + 1'b1;
                    end else if (rx_cnt != 0) begin
                        // host stalled mid-frame -> resynchronise
                        if (idle_cnt == TIMEOUT_CLKS - 1) begin
                            rx_cnt   <= 0;
                            idle_cnt <= 0;
                        end else
                            idle_cnt <= idle_cnt + 1'b1;
                    end
                end

                //  clear accumulators 
                S_CLR: begin
                    arr_clr <= 1'b1;
                    t       <= 0;
                    state   <= S_RUN;
                end

                //  feed skewed operands 
                // Row i receives A[i][t-i]  (zero outside 0 <= t-i < N)
                // Col j receives B[t-j][j]  (zero outside 0 <= t-j < N)
                S_RUN: begin
                    for (i = 0; i < N; i = i + 1) begin
                        if (t >= i && t < i + N) begin
                            a_edge_flat[DW*i +: DW] <= mat[N*i + (t - i)];
                            b_edge_flat[DW*i +: DW] <= mat[N*N + N*(t - i) + i];
                        end else begin
                            a_edge_flat[DW*i +: DW] <= 0;
                            b_edge_flat[DW*i +: DW] <= 0;
                        end
                    end

                    if (t == RUN_CYCLES - 1) begin
                        c_reg  <= c_flat;          // all PEs have finished by now
                        state  <= S_TX_LOAD;
                        tx_cnt <= 0;
                    end
                    t <= t + 1'b1;
                end

                //  send 256 result bytes 
                S_TX_LOAD: begin
                    a_edge_flat <= 0;
                    b_edge_flat <= 0;
                    if (!tx_busy) begin
                        // result index = tx_cnt[7:2], byte (MSB first) = tx_cnt[1:0]
                        tx_byte <= c_reg[ACW*tx_cnt[7:2] + 8*(3 - tx_cnt[1:0]) +: 8];
                        tx_dv   <= 1'b1;
                        state   <= S_TX_WAIT;
                    end
                end

                S_TX_WAIT: begin
                    if (tx_done) begin
                        if (tx_cnt == NOUT-1) begin
                            jobs  <= jobs + 1'b1;
                            state <= S_RX;
                        end else begin
                            tx_cnt <= tx_cnt + 1'b1;
                            state  <= S_TX_LOAD;
                        end
                    end
                end

                default: state <= S_RX;
            endcase
        end
    end

    assign led[0]    = (state == S_RX);
    assign led[1]    = (state == S_CLR) || (state == S_RUN);
    assign led[2]    = (state == S_TX_LOAD) || (state == S_TX_WAIT);
    assign led[7:3]  = 5'd0;
    assign led[15:8] = jobs;
endmodule
