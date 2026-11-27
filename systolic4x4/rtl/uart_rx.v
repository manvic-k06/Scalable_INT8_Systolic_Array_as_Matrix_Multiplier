
// uart_rx.v  -  8N1 UART receiver
// CLKS_PER_BIT = f_clk / baud   (100 MHz / 115200 = 868)
// o_dv pulses high for exactly one clock when a byte is ready on o_byte.

module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       i_rx,      // serial line (idle high)
    output reg        o_dv,      // data valid pulse
    output reg  [7:0] o_byte
);
    localparam IDLE  = 3'd0,
               START = 3'd1,
               DATA  = 3'd2,
               STOP  = 3'd3,
               DONE  = 3'd4;

    // Two-flop synchronizer: the RX pin is asynchronous to clk
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        rx_meta <= i_rx;
        rx_sync <= rx_meta;
    end

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            o_dv    <= 1'b0;
            o_byte  <= 8'd0;
        end else begin
            o_dv <= 1'b0;
            case (state)
                IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (rx_sync == 1'b0)          // falling edge = start bit
                        state <= START;
                end

                // Wait half a bit, re-check the line is still low (glitch filter)
                START: begin
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        clk_cnt <= 0;
                        state   <= (rx_sync == 1'b0) ? DATA : IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                // Sample in the middle of each data bit, LSB first
                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt         <= 0;
                        o_byte[bit_idx] <= rx_sync;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        o_dv    <= 1'b1;
                        state   <= DONE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                DONE:    state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
