module usb_bit_stuffing_wrapper (
    input logic clk12,
    input logic RST,
    input logic isSendingPhase,
    input logic dataIn,
    output logic ready_valid,
    output logic dataOut,
    output logic error
);

    usb_bit_unstuff unstuffer(
        .clk12(clk12),
        .RST(RST),
        .valid(ready_valid),
        .data(isSendingPhase && !ready_valid ? 1'b0 : dataIn),
        .error(error)
    );

    assign dataOut = ready_valid ? dataIn : 1'b0;

endmodule
