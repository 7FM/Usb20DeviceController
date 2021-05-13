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

    // Prevent propagation of meta stability by double flopping
    logic doubleFlopP, doubleFlopP_negedge, doubleFlopN;

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

`ifdef DP_REGISTERED_INPUT
    assign doubleFlopP = inP;
    assign doubleFlopN = inN;
    assign doubleFlopP_negedge = inP_negedge;
`else
    assign inP_negedge = inP;
`endif

`else // SIMULATION CASE
    // Always double flop in simulation

    // Tristate output logic
    assign pinP_OUT = OUT_EN ? dataOutP : 1'bz;
    assign pinN_OUT = OUT_EN ? dataOutN : 1'bz;

    assign inP = pinP;
    assign inP_negedge = pinP;
    assign inN = pinN;
`endif

    initial begin
`ifndef RUN_SIM
`ifndef DP_REGISTERED_INPUT
        doubleFlopP = 1'b1;
        doubleFlopP_negedge = 1'b1;
        doubleFlopN = 1'b0;
`endif
`else
        doubleFlopP = 1'b1;
        doubleFlopP_negedge = 1'b1;
        doubleFlopN = 1'b0;
`endif
        dataInP = 1'b1;
        dataInP_negedge = 1'b1;
        dataInN = 1'b0;
    end

`ifndef RUN_SIM
`ifndef DP_REGISTERED_INPUT
    always_ff @(negedge clk48) begin
        doubleFlopP_negedge <= inP_negedge;
    end
`endif
`else // SIMULATION CASE
    always_ff @(negedge clk48) begin
        doubleFlopP_negedge <= inP_negedge;
    end
`endif

    always_ff @(posedge clk48) begin
`ifndef RUN_SIM
`ifndef DP_REGISTERED_INPUT
        doubleFlopP <= inP;
        doubleFlopN <= inN;
`endif
`else
        doubleFlopP <= inP;
        doubleFlopN <= inN;
`endif

        dataInP <= OUT_EN ? 1'b1 : doubleFlopP;
        dataInP_negedge <= OUT_EN ? 1'b1 : doubleFlopP_negedge;
        dataInN <= OUT_EN ? 1'b0 : doubleFlopN;
    end

endmodule
