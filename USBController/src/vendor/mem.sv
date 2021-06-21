// Some generic memory with dual port like interface
module mem #(
    parameter DEPTH = 512,
    parameter DATA_WID = 8
)(
    input logic CLK,

    input logic WEN,
    input logic [$clog2(DEPTH):0] waddr,
    input logic [DATA_WID-1:0] wdata,

    input logic [$clog2(DEPTH):0] raddr,
    output logic [DATA_WID-1:0] rdata
);
    logic [DATA_WID-1:0] mem [0:DEPTH-1];

    always @(posedge CLK) begin
        if (WEN) begin
           mem[waddr] <= wdata;
        end

        rdata <= mem[raddr];
    end
endmodule
