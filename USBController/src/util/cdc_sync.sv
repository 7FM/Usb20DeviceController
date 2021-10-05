module cdc_sync (
    input logic clk,
    input logic in,
    output logic out
);

    logic in_sync;

    always_ff @(posedge clk) begin
        {out, in_sync} <= {in_sync, in};
    end

endmodule
