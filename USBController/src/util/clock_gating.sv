module clock_gating#(
    parameter INIT_VALUE = 1'b1,
    parameter USE_FFs = 0
)(
    input logic clk_i,
    input logic clkEn_i,
    output logic clk_o
);

    logic latched_en;

    assign clk_o = clk_i && latched_en;

    initial begin
        latched_en = INIT_VALUE[0];
    end
generate
    if (USE_FFs) begin
        logic sync_en;

        initial begin
            sync_en = INIT_VALUE[0];
        end

        always_ff @(posedge clk_i) begin
            sync_en <= clkEn_i;
        end

        always @(negedge clk_i) begin
            latched_en <= clkEn_i;
        end

    end else begin
        always_latch begin
            if (~clk_i) begin
                latched_en = clkEn_i;
            end
        end
    end
endgenerate

endmodule
