
// top.v  -  UART-connected 4x4 INT8 systolic-array matrix multiplier
// FSM:  RX (collect 32 bytes) -> CLR -> RUN (16 cycles) -> TX (64 bytes) -> RX
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
    localparam N = 4, DW = 8, ACW = 32;

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

    
    // Operand storage: mat[0..15] = A, mat[16..31] = B
    
    reg signed [7:0] mat [0:31];

    
    // Systolic array
    
    reg                  arr_clr;
    reg  [N*DW-1:0]      a_edge_flat, b_edge_flat;
    wire [N*N*ACW-1:0]   c_flat;
    reg  [N*N*ACW-1:0]   c_reg;

    systolic_array_4x4 #(.N(N), .DW(DW), .ACW(ACW)) u_array (
        .clk(clk), .clr(arr_clr),
        .a_edge_flat(a_edge_flat), .b_edge_flat(b_edge_flat),
        .c_flat(c_flat));

    
    // Control FSM
    
    localparam S_RX      = 3'd0,
               S_CLR     = 3'd1,
               S_RUN     = 3'd2,
               S_TX_LOAD = 3'd3,
               S_TX_WAIT = 3'd4;

    // 3N-2 = 10 cycles of skewed input + pipeline drain; 16 is a safe round number
    localparam RUN_CYCLES = 16;

    reg [2:0]  state;
    reg [5:0]  rx_cnt;        // 0..31
    reg [4:0]  t;             // compute time step
    reg [5:0]  tx_cnt;        // 0..63
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
                //  receive 32 operand bytes 
                S_RX: begin
                    a_edge_flat <= 0;
                    b_edge_flat <= 0;
                    if (rx_dv) begin
                        mat[rx_cnt] <= rx_byte;
                        idle_cnt    <= 0;
                        if (rx_cnt == 6'd31) begin
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

                // clear accumulators 
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
                            b_edge_flat[DW*i +: DW] <= mat[16 + N*(t - i) + i];
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

                //  send 64 result bytes 
                S_TX_LOAD: begin
                    a_edge_flat <= 0;
                    b_edge_flat <= 0;
                    if (!tx_busy) begin
                        // result index = tx_cnt[5:2], byte (MSB first) = tx_cnt[1:0]
                        tx_byte <= c_reg[ACW*tx_cnt[5:2] + 8*(3 - tx_cnt[1:0]) +: 8];
                        tx_dv   <= 1'b1;
                        state   <= S_TX_WAIT;
                    end
                end

                S_TX_WAIT: begin
                    if (tx_done) begin
                        if (tx_cnt == 6'd63) begin
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
