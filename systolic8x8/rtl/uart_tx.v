
// uart_tx.v  -  8N1 UART transmitter
// Pulse i_dv for one clock with i_byte valid while o_busy is low.
// o_done pulses for one clock after the stop bit has been sent.
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       i_dv,
    input  wire [7:0] i_byte,
    output reg        o_tx,      // serial line (idle high)
    output reg        o_busy,
    output reg        o_done
);
    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            shreg   <= 0;
            o_tx    <= 1'b1;
            o_busy  <= 1'b0;
            o_done  <= 1'b0;
        end else begin
            o_done <= 1'b0;
            case (state)
                IDLE: begin
                    o_tx    <= 1'b1;
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if (i_dv) begin
                        shreg  <= i_byte;
                        o_busy <= 1'b1;
                        state  <= START;
                    end
                end

                START: begin
                    o_tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        state   <= DATA;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                DATA: begin
                    o_tx <= shreg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state   <= STOP;
                        end else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end

                STOP: begin
                    o_tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        o_busy  <= 1'b0;
                        o_done  <= 1'b1;
                        state   <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1'b1;
                end
            endcase
        end
    end
endmodule
