module usb_dp(
    inout logic pinP,
    inout logic pinN,
    input logic OUT_EN,
    input logic dataOutP,
    input logic dataOutN,
    output logic dataInP,
    output logic dataInN,
);

`ifndef RUN_SIM
  logic inP, inN;

  SB_IO #(
    .PIN_TYPE(6'b1010_01) // tristatable output and normal input
  ) buffer(
    .PACKAGE_PIN(pinP),
    .OUTPUT_ENABLE(OUT_EN),
    .D_IN_0(inP),
    .D_OUT_0(dataOutP)
  );
  SB_IO #(
    .PIN_TYPE(6'b1010_01) // tristatable output and normal input
  ) buffer(
    .PACKAGE_PIN(pinN),
    .OUTPUT_ENABLE(OUT_EN),
    .D_IN_0(inN),
    .D_OUT_0(dataOutN)
  );

  assign dataInP = OUT_EN ? 1'b1 : inP;
  assign dataInN = OUT_EN ? 1'b0 : inN;
`else
    // Tristate output logic
    assign pinP = OUT_EN ? dataOutP : 1'bz;
    assign pinN = OUT_EN ? dataOutN : 1'bz;
    assign dataInP = OUT_EN ? 1'b1 : pinP;
    assign dataInN = OUT_EN ? 1'b0 : pinN;
`endif

endmodule