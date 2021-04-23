module clock_gating#(
    parameter INIT_VALUE = 1'b1,
    parameter USE_FFs = 0
)(
    input logic CLK_IN,
    input logic CLK_EN,
    output logic CLK_OUT
);

    logic latched_en;

    assign CLK_OUT = CLK_IN && latched_en;

    initial begin
        latched_en = INIT_VALUE[0];
    end
generate
    if (USE_FFs) begin
        logic sync_en;

        initial begin
            sync_en = INIT_VALUE[0];
        end

        always_ff @(posedge CLK_IN) begin
            sync_en <= CLK_EN;
        end

        always @(negedge CLK_IN) begin
            latched_en <= CLK_EN;
        end

    end else begin
        always_latch begin
            if (~CLK_IN) begin
                latched_en = CLK_EN;
            end
        end
    end
endgenerate

endmodule