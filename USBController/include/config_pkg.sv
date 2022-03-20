`ifndef CONFIG_PKG_SV
`define CONFIG_PKG_SV

package config_pkg;

`define DEBUG_LEDS
// Select which part of the usb controller should provide the debug leds
`define DEBUG_USB_RX
`ifndef DEBUG_USB_RX
`define DEBUG_USB_PE
`endif

// Select which part of the usb receiveer should provide the debug leds
`ifdef DEBUG_USB_RX
`define DEBUG_USB_RX_IFACE
`ifndef DEBUG_USB_RX_IFACE
`define DEBUG_USB_RX_INTERNAL
`endif
`endif

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

// Configuration limitations:
//TODO reasonable values
// Max. amount of configurations this device can have!
localparam MAX_CONFIG_DESCRIPTORS = 2;
// Max. amount of interfaces per configuration
localparam MAX_INTERFACE_DESCRIPTORS = 2;
// String descriptors:
localparam SUPPORTED_LANGUAGES = 1;
localparam MAX_STRING_LEN = 20;
localparam MAX_STRING_DESCRIPTORS = 10;

// Allow overwriting usb endpoint modules to use if specific functionality is desired
`ifndef EP_0_MODULE
`define EP_0_MODULE(USB_DEV_EP_CONF) \
        usb_endpoint_0 #(                                                \
            .USB_DEV_EP_CONF(USB_DEV_EP_CONF)                            \
        )
`endif
`ifndef EP_1_MODULE
`define EP_1_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_2_MODULE
`define EP_2_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_3_MODULE
`define EP_3_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_4_MODULE
`define EP_4_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_5_MODULE
`define EP_5_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_6_MODULE
`define EP_6_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_7_MODULE
`define EP_7_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_8_MODULE
`define EP_8_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_9_MODULE
`define EP_9_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_10_MODULE
`define EP_10_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_11_MODULE
`define EP_11_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_12_MODULE
`define EP_12_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_13_MODULE
`define EP_13_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_14_MODULE
`define EP_14_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif
`ifndef EP_15_MODULE
`define EP_15_MODULE(epConfig) usb_endpoint #(.EP_CONF(epConfig))
`endif

`ifndef TOP_EP_CONSUMER
// By default add a dummy consumer which echo's the received data to the to be send data of one endpoint index
`define TOP_EP_CONSUMER(USB_DEV_EP_CONF) echo_endpoints #(.USB_DEV_EP_CONF(USB_DEV_EP_CONF))
`endif

endpackage

`endif
