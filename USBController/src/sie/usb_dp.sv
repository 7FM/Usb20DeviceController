module usb_dp(
    input logic clk48,
    inout logic pinP,
    inout logic pinN,
    input logic OUT_EN,
    input logic dataOutP,
    input logic dataOutN,
    output logic dataInP,
    output logic dataInN,
);

    logic inP, inN;
`ifndef RUN_SIM

    SB_IO #(
        .PIN_TYPE(6'b1010_01) // tristatable output and normal input
    ) buffer(
        .OUTPUT_ENABLE(OUT_EN),
        .PACKAGE_PIN(pinP),
        .D_IN_0(inP),
        .D_OUT_0(dataOutP)
    );
    SB_IO #(
        .PIN_TYPE(6'b1010_01) // tristatable output and normal input
    ) buffer(
        .OUTPUT_ENABLE(OUT_EN),
        .PACKAGE_PIN(pinN),
        .D_IN_0(inN),
        .D_OUT_0(dataOutN)
    );

`else
    // Tristate output logic
    assign pinP = OUT_EN ? dataOutP : 1'bz;
    assign pinN = OUT_EN ? dataOutN : 1'bz;

    assign inP = pinP;
    assign inN = pinN;
`endif

    always_ff @(posedge clk48) begin
        dataInP <= OUT_EN ? 1'b1 : inP;
        dataInN <= OUT_EN ? 1'b0 : inN;
    end

endmodule