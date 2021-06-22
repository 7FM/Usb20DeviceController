module clock_mux(
    input logic clk1_i,
    input logic clk2_i,
    input logic clkSel_i,
    output logic clk_o
);

    logic clk1_sel_sync_1, clk1_sel_sync_2;
    logic clk2_sel_sync_1, clk2_sel_sync_2;

    initial begin
        clk1_sel_sync_1 = 0;
        clk1_sel_sync_2 = 0;
        clk2_sel_sync_1 = 0;
        clk2_sel_sync_2 = 0;
    end

    always_ff @(posedge clk1_i) begin
        clk1_sel_sync_1 <= ~clk2_sel_sync_2 && clkSel_i;
    end
    always_ff @(negedge clk1_i) begin
        clk1_sel_sync_2 <= clk1_sel_sync_1;
    end

    always_ff @(posedge clk2_i) begin
        clk2_sel_sync_1 <= ~clk1_sel_sync_2 && ~clkSel_i;
    end
    always_ff @(negedge clk2_i) begin
        clk2_sel_sync_2 <= clk2_sel_sync_1;
    end

    assign clk_o = (clk1_i && clk1_sel_sync_2) || (clk2_i && clk2_sel_sync_2);

endmodule
