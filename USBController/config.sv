`ifndef CONFIG_SV
`define CONFIG_SV

// $icepll -i 12MHz -o 48Mhz
// F_PLLOUT:   48 MHz (achieved)
`define PLL_CLK_DIVR 4'b0000
`define PLL_CLK_DIVF 7'b0111111
`define PLL_CLK_DIVQ 3'b100
`define PLL_CLK_FILTER_RANGE 3'b001
`define PLL_CLK_RESETB 1'b1
`define PLL_CLK_BYPASS 1'b0

`endif
