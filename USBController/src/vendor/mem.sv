// Some generic memory with dual port like interface
module mem #(
    parameter DEPTH = 512,
    parameter DATA_WID = 8,
    localparam ADDR_WID = $clog2(DEPTH)
)(
    input logic clk_i,

    input logic wEn_i,
    input logic [ADDR_WID-1:0] wAddr_i,
    input logic [DATA_WID-1:0] wData_i,

    input logic [ADDR_WID-1:0] rAddr_i,
    output logic [DATA_WID-1:0] rData_o
);
    logic [DATA_WID-1:0] mem [0:DEPTH-1];

    always @(posedge clk_i) begin
        if (wEn_i) begin
           mem[wAddr_i] <= wData_i;
        end

        rData_o <= mem[rAddr_i];
    end
endmodule
