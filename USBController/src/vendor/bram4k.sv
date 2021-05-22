// 4k dual port block ram: 8 Bits in/output data with a depth of 512
module bram4k (
    input logic CLK,

    input logic WEN,
    input logic [8:0] waddr,
    input logic [7:0] wdata,

    input logic [8:0] raddr,
    output logic [7:0] rdata
);
    logic [7:0] mem [0:511];

    always @(posedge CLK) begin
        if (WEN) begin
           mem[waddr] <= wdata;
        end

        rdata <= mem[raddr];
    end
endmodule
