`ifndef CONFIG_PKG_SV
`define CONFIG_PKG_SV

package config_pkg;

// $icepll -i 12MHz -o 48Mhz
// F_PLLOUT:   48 MHz (achieved)
localparam PLL_CLK_DIVR = 4'b0000;
localparam PLL_CLK_DIVF = 7'b0111111;
localparam PLL_CLK_DIVQ = 3'b100;
localparam PLL_CLK_FILTER_RANGE = 3'b001;
localparam PLL_CLK_RESETB = 1'b1;
localparam PLL_CLK_BYPASS = 1'b0;

// enable by IO block provided registered inputs for the differential input pins
`define DP_REGISTERED_INPUT

// Debug LEDs to show different types of errors!
`define USE_DEBUG_LEDS

endpackage

`endif
