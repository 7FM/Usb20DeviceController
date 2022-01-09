`include "config_pkg.sv"

module usb_serial_frontend(
    input logic clk48_i,

    // Pins
`ifdef RUN_SIM
    input logic pinP,
    output logic pinP_o,
    input logic pinN,
    output logic pinN_o,
`else
    // On downstream facing ports, RPD resistors (15 kΩ ±5%) must be connected from D+ and D- to ground
    inout logic pinP,
    inout logic pinN,
`endif

    // Data signals
    input logic dataOutEn_i,
    input logic dataOutP_i,
    input logic dataOutN_i,
    output logic dataInP_o,
    output logic dataInP_negedge_o,

    // Service signals
    output logic isValidDPSignal_o,
    output logic eopDetected_o,
    input logic ackEOP_i,
    output logic usbResetDetected_o,
    input logic ackUsbRst_i
);

    /*
    Differential Signal:
                                 __   _     _   _     ____
                            D+ :   \_/ \___/ \_/ \___/
                                    _   ___   _           
                            D- : __/ \_/   \_/ \__________
    Differential decoding:          K J K K J K J 0 0 J J
                                                  ^------------ SM0/SE0 with D+=D-=LOW analogously exists SM1/SE1 with D+=D-=HIGH
    NRZI decoding:                  0 0 0 1 0 0 0 ? ? 0 1
    (Non-Return-to-Zero Inverted): logical 0 is transmitted as transition -> either from J to K or from K to J
                                   logical 1 is transmitted as NO transition -> stay at previous level
    */

    // Service signals
    logic dataInN;
    assign isValidDPSignal_o = dataInN ^ dataInP_o;

    eop_reset_detect eopAndResetDetect(
        .clk48_i(clk48_i),
        .dataInP_i(dataInP_o),
        .dataInN_i(dataInN),
        .eopDetect_o(eopDetected_o),
        .ackEOP_i(ackEOP_i),
        .usbRst_o(usbResetDetected_o),
        .ackUsbRst_i(ackUsbRst_i)
    );

    // Input & output logic
    logic inP, inP_negedge, inN;

`ifdef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
`undef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
`endif

`ifndef DP_REGISTERED_INPUT
    `define USB_DP_ADD_NEGEDGE_SYNC_BLOCK
    localparam DOUBLE_FLOP_SHIFT_REG_LENGTH = 2;
`else
`ifdef FALLBACK_DEVICE
    `define USB_DP_ADD_NEGEDGE_SYNC_BLOCK
    localparam DOUBLE_FLOP_SHIFT_REG_LENGTH = 2;
`else
    localparam DOUBLE_FLOP_SHIFT_REG_LENGTH = 1;
`endif
`endif

    // inP_negedge will always be an register no matter the settings -> we need one double flopping stage less
    localparam DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH = ((DOUBLE_FLOP_SHIFT_REG_LENGTH-1) == 0 ? 1 : DOUBLE_FLOP_SHIFT_REG_LENGTH-1);

    // Prevent propagation of meta stability by double flopping
    logic [DOUBLE_FLOP_SHIFT_REG_LENGTH-1:0] doubleFlopP, doubleFlopN;
    logic [DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-1:0] doubleFlopP_negedge;

`ifndef FALLBACK_DEVICE
`ifdef LATTICE_ICE_40
    SB_IO #(
        .PULLUP(1'b0),
`ifndef DP_REGISTERED_INPUT
        .PIN_TYPE(6'b1010_01) // tristatable output and normal input
`else
        .PIN_TYPE(6'b1010_00) // tristatable output and registered input
`endif
    ) buffer1(
        .OUTPUT_ENABLE(dataOutEn_i),
        .PACKAGE_PIN(pinP),
        .D_IN_0(inP),
`ifdef DP_REGISTERED_INPUT
        .D_IN_1(inP_negedge), // Also use negedge synced input register
`endif
        .D_OUT_0(dataOutP_i)
`ifdef DP_REGISTERED_INPUT
        ,.CLOCK_ENABLE(1'b1),
        .INPUT_CLK(clk48_i)
`endif
    );

    SB_IO #(
        .PULLUP(1'b0),
`ifndef DP_REGISTERED_INPUT
        .PIN_TYPE(6'b1010_01) // tristatable output and normal input
`else
        .PIN_TYPE(6'b1010_00) // tristatable output and registered input
`endif
    ) buffer2(
        .OUTPUT_ENABLE(dataOutEn_i),
        .PACKAGE_PIN(pinN),
        .D_IN_0(inN),
        .D_OUT_0(dataOutN_i)
`ifdef DP_REGISTERED_INPUT
        ,.CLOCK_ENABLE(1'b1),
        .INPUT_CLK(clk48_i)
`endif
    );
`endif
`else // Fallback CASE
    // Tristate output logic
`ifdef RUN_SIM
    assign pinP_o = dataOutEn_i ? dataOutP_i : 1'b1;
    assign pinN_o = dataOutEn_i ? dataOutN_i : 1'b0;
`else
    assign pinP = dataOutEn_i ? dataOutP_i : 1'bz;
    assign pinN = dataOutEn_i ? dataOutN_i : 1'bz;
`endif

    assign inP = pinP;
    assign inN = pinN;
`endif

    localparam dataOutEn_i_SHIFT_REG_LENGTH = 2;
    logic [dataOutEn_i_SHIFT_REG_LENGTH-1:0] outEnShiftReg;
    initial begin
        outEnShiftReg = {dataOutEn_i_SHIFT_REG_LENGTH{1'b0}};
        doubleFlopP = {DOUBLE_FLOP_SHIFT_REG_LENGTH{1'b1}};
        doubleFlopP_negedge = {DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH{1'b1}};
        doubleFlopN = {DOUBLE_FLOP_SHIFT_REG_LENGTH{1'b0}};
        dataInP_o = 1'b1;
        dataInP_negedge_o = 1'b1;
        dataInN = 1'b0;
`ifdef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
        inP_negedge = 1'b1;
`endif
    end

`ifdef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
    always_ff @(negedge clk48_i) begin
        inP_negedge <= inP;
    end
`endif


    always_ff @(posedge clk48_i) begin
        outEnShiftReg <= {outEnShiftReg[dataOutEn_i_SHIFT_REG_LENGTH-2:0], dataOutEn_i};

        doubleFlopP[0] <= inP;
        doubleFlopN[0] <= inN;
        doubleFlopP_negedge[0] <= inP_negedge;

        dataInP_o <= outEnShiftReg[dataOutEn_i_SHIFT_REG_LENGTH-1] ? 1'b1 : doubleFlopP[DOUBLE_FLOP_SHIFT_REG_LENGTH-1];
        dataInP_negedge_o <= outEnShiftReg[dataOutEn_i_SHIFT_REG_LENGTH-1] ? 1'b1 : doubleFlopP_negedge[DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-1];
        dataInN <= outEnShiftReg[dataOutEn_i_SHIFT_REG_LENGTH-1] ? 1'b0 : doubleFlopN[DOUBLE_FLOP_SHIFT_REG_LENGTH-1];
    end

    generate
        if (DOUBLE_FLOP_SHIFT_REG_LENGTH > 1) begin
            always_ff @(posedge clk48_i) begin
                doubleFlopP[DOUBLE_FLOP_SHIFT_REG_LENGTH-1:1] <= doubleFlopP[DOUBLE_FLOP_SHIFT_REG_LENGTH-2:0];
                doubleFlopN[DOUBLE_FLOP_SHIFT_REG_LENGTH-1:1] <= doubleFlopN[DOUBLE_FLOP_SHIFT_REG_LENGTH-2:0];
            end
        end
        if (DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH > 1) begin
            always_ff @(posedge clk48_i) begin
                doubleFlopP_negedge[DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-1:1] <= doubleFlopP_negedge[DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-2:0];
            end
        end
    endgenerate

endmodule
