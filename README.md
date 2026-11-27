# Scalable INT8 Systolic Array as Matrix Multiplier

Output-stationary systolic-array matrix multipliers in Verilog, built at two sizes, **4×4** and **8×8**, from the same processing element. They multiply signed INT8 matrices with 32-bit accumulation, take operands over UART, and are implemented on a Xilinx Artix-7 FPGA (Basys 3, `xc7a35tcpg236-1`).

## Architecture

```
PC ──UART──► operand store ──► skew logic ──► N×N PE array ──► result register ──UART──► PC
                                   ▲                 ▲
                                   └── control FSM ──┘
```

- **Processing element:** an 8×8 signed multiplier and a 32-bit accumulator. It forwards A to the right and B downwards, so each operand is read once and reused N times.
- **Input skew:** row *i* of A and column *j* of B are delayed by *i* and *j* cycles, so PE(*i*,*j*) receives the matching pair `k = cycle − 1 − i − j`.
- **Latency:** the array is busy for `3N − 2` cycles per product (10 for 4×4, 22 for 8×8), against `N³` cycles for a single MAC unit (64 and 512).
