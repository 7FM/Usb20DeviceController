module usb_bit_stuffing_wrapper (
    input logic clk12_i,
    input logic rst_i,
    input logic isSendingPhase_i,
    input logic data_i,
    output logic ready_valid_o,
    output logic data_o,
    output logic error_o
);

    usb_bit_unstuff unstuffer(
        .clk12_i(clk12_i),
        .rst_i(rst_i),
        .valid_o(ready_valid_o),
        .data_i(isSendingPhase_i && !ready_valid_o ? 1'b0 : data_i),
        .error_o(error_o)
    );

    assign data_o = ready_valid_o ? data_i : 1'b0;

endmodule
