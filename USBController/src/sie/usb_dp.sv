`include "config_pkg.sv"

module usb_dp(
    input logic clk48,
`ifdef RUN_SIM
    input logic pinP,
    output logic pinP_OUT,
    input logic pinN,
    output logic pinN_OUT,
`else
    inout logic pinP,
    inout logic pinN,
`endif
    input logic OUT_EN,
    input logic dataOutP,
    input logic dataOutN,
    output logic dataInP,
    output logic dataInP_negedge,
    output logic dataInN
);

    logic inP, inP_negedge, inN;

`ifdef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
`undef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
`endif

`ifndef DP_REGISTERED_INPUT
    `define USB_DP_ADD_NEGEDGE_SYNC_BLOCK
    localparam DOUBLE_FLOP_SHIFT_REG_LENGTH = 2;
`else
`ifdef RUN_SIM
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

`ifndef RUN_SIM

    SB_IO #(
`ifndef DP_REGISTERED_INPUT
        .PIN_TYPE(6'b1010_01) // tristatable output and normal input
`else
        .PIN_TYPE(6'b1010_00) // tristatable output and registered input
`endif
    ) buffer1(
        .OUTPUT_ENABLE(OUT_EN),
        .PACKAGE_PIN(pinP),
        .D_IN_0(inP),
`ifdef DP_REGISTERED_INPUT
        .D_IN_1(inP_negedge), // Also use negedge synced input register
`endif
        .D_OUT_0(dataOutP)
`ifdef DP_REGISTERED_INPUT
        ,.CLOCK_ENABLE(1'b1),
        .INPUT_CLK(clk48)
`endif
    );

    SB_IO #(
`ifndef DP_REGISTERED_INPUT
        .PIN_TYPE(6'b1010_01) // tristatable output and normal input
`else
        .PIN_TYPE(6'b1010_00) // tristatable output and registered input
`endif
    ) buffer2(
        .OUTPUT_ENABLE(OUT_EN),
        .PACKAGE_PIN(pinN),
        .D_IN_0(inN),
        .D_OUT_0(dataOutN)
`ifdef DP_REGISTERED_INPUT
        ,.CLOCK_ENABLE(1'b1),
        .INPUT_CLK(clk48)
`endif
    );

`else // SIMULATION CASE
    // Tristate output logic
    assign pinP_OUT = OUT_EN ? dataOutP : 1'bz;
    assign pinN_OUT = OUT_EN ? dataOutN : 1'bz;

    assign inP = pinP;
    assign inN = pinN;
`endif

    localparam OUT_EN_SHIFT_REG_LENGTH = 2;
    logic [OUT_EN_SHIFT_REG_LENGTH-1:0] outEnShiftReg;
    initial begin
        outEnShiftReg = {OUT_EN_SHIFT_REG_LENGTH{1'b0}};
        doubleFlopP = {DOUBLE_FLOP_SHIFT_REG_LENGTH{1'b1}};
        doubleFlopP_negedge = {DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH{1'b1}};
        doubleFlopN = {DOUBLE_FLOP_SHIFT_REG_LENGTH{1'b0}};
        dataInP = 1'b1;
        dataInP_negedge = 1'b1;
        dataInN = 1'b0;
`ifdef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
        inP_negedge = 1'b1;
`endif
    end

`ifdef USB_DP_ADD_NEGEDGE_SYNC_BLOCK
    always_ff @(negedge clk48) begin
        inP_negedge <= inP;
    end
`endif


    always_ff @(posedge clk48) begin
        outEnShiftReg <= {outEnShiftReg[OUT_EN_SHIFT_REG_LENGTH-2:0], OUT_EN};

        doubleFlopP[0] <= inP;
        doubleFlopN[0] <= inN;
        doubleFlopP_negedge[0] <= inP_negedge;

        dataInP <= outEnShiftReg[OUT_EN_SHIFT_REG_LENGTH-1] ? 1'b1 : doubleFlopP[DOUBLE_FLOP_SHIFT_REG_LENGTH-1];
        dataInP_negedge <= outEnShiftReg[OUT_EN_SHIFT_REG_LENGTH-1] ? 1'b1 : doubleFlopP_negedge[DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-1];
        dataInN <= outEnShiftReg[OUT_EN_SHIFT_REG_LENGTH-1] ? 1'b0 : doubleFlopN[DOUBLE_FLOP_SHIFT_REG_LENGTH-1];
    end

    generate
        if (DOUBLE_FLOP_SHIFT_REG_LENGTH > 1) begin
            always_ff @(posedge clk48) begin
                doubleFlopP[DOUBLE_FLOP_SHIFT_REG_LENGTH-1:1] <= doubleFlopP[DOUBLE_FLOP_SHIFT_REG_LENGTH-2:0];
                doubleFlopN[DOUBLE_FLOP_SHIFT_REG_LENGTH-1:1] <= doubleFlopN[DOUBLE_FLOP_SHIFT_REG_LENGTH-2:0];
            end
        end
        if (DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH > 1) begin
            always_ff @(posedge clk48) begin
                doubleFlopP_negedge[DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-1:1] <= doubleFlopP_negedge[DOUBLE_FLOP_NEGEDGE_SHIFT_REG_LENGTH-2:0];
            end
        end
    endgenerate

endmodule
