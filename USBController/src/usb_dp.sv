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
  SB_IO #(
    .PIN_TYPE(6'b1010_01) // tristatable output and normal input
  ) buffer(
    .PACKAGE_PIN(pinP),
    .OUTPUT_ENABLE(OUT_EN),
    .D_IN_0(dataInP),
    .D_OUT_0(dataOutP)
  );
  SB_IO #(
    .PIN_TYPE(6'b1010_01) // tristatable output and normal input
  ) buffer(
    .PACKAGE_PIN(pinN),
    .OUTPUT_ENABLE(OUT_EN),
    .D_IN_0(dataInN),
    .D_OUT_0(dataOutN)
  );
`else
    // Tristate output logic
    assign pinP = EN ? dataOutP : 1'bz;
    assign pinN = EN ? dataOutN : 1'bz;
    assign dataInP = EN ? 1'b1 : pinP;
    assign dataInN = EN ? 1'b0 : pinN;
`endif

endmodule