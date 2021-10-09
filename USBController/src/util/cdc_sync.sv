module cdc_sync #(
    parameter WID = 1,
    parameter INIT_VALUE = 1'b0
)(
    input logic clk,
    input logic [WID-1:0] in,
    output logic [WID-1:0] out
);

    //TODO initialization & reset logic!

    logic [WID-1:0] in_sync;

    initial begin
        out = INIT_VALUE[WID-1:0];
        in_sync = INIT_VALUE[WID-1:0];
    end

    always_ff @(posedge clk) begin
        {out, in_sync} <= {in_sync, in};
    end

endmodule
