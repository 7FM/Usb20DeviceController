`ifndef CONFIG_PKG_SV
`define CONFIG_PKG_SV

package config_pkg;


// General Settings
// enable by IO block provided registered inputs for the differential input pins
`define DP_REGISTERED_INPUT


// Supported devices
`ifndef RUN_SIM
`define LATTICE_ICE_40
`else
`define FALLBACK_DEVICE
`endif

// Vendor/Device Specific Settings
`ifdef LATTICE_ICE_40
// $icepll -i 12MHz -o 48Mhz
// F_PLLOUT:   48 MHz (achieved)
localparam PLL_CLK_DIVR = 4'b0000;
localparam PLL_CLK_DIVF = 7'b0111111;
localparam PLL_CLK_DIVQ = 3'b100;
localparam PLL_CLK_FILTER_RANGE = 3'b001;
localparam PLL_CLK_RESETB = 1'b1;
localparam PLL_CLK_BYPASS = 1'b0;
`endif

endpackage

`endif
