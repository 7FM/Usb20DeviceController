module gray_code_encoder #(
    parameter WID = 2
)(
    input logic [WID-1:0] in,
    output logic [WID-1:0] out
);

    // out = (in >> 1) ^ in
    assign out = {1'b0, in[WID-1:1]} ^ in;

endmodule
