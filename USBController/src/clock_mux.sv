module clock_mux(
    input logic CLK_1,
    input logic CLK_2,
    input logic SEL,
    output logic CLK
);

    logic clk1_sel_sync_1, clk1_sel_sync_2;
    logic clk2_sel_sync_1, clk2_sel_sync_2;

    initial begin
        clk1_sel_sync_1 = 0;
        clk1_sel_sync_2 = 0;
        clk2_sel_sync_1 = 0;
        clk2_sel_sync_2 = 0;
    end

    always_ff @(posedge CLK_1) begin
        clk1_sel_sync_1 <= ~clk2_sel_sync_2 && SEL;
    end
    always_ff @(negedge CLK_1) begin
        clk1_sel_sync_2 <= clk1_sel_sync_1;
    end

    always_ff @(posedge CLK_2) begin
        clk2_sel_sync_1 <= ~clk1_sel_sync_2 && ~SEL;
    end
    always_ff @(negedge CLK_2) begin
        clk2_sel_sync_2 <= clk2_sel_sync_1;
    end

    assign CLK = (CLK_1 && clk1_sel_sync_2) || (CLK_2 && clk2_sel_sync_2);

endmodule