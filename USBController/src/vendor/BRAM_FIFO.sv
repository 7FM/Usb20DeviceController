module BRAM_FIFO #(
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8
)(
    input logic CLK,

    // Provide transactional read & write behaviour to allow reseting the values on failures without overwriting/loosing i.e. not yet send data or discarding corrupt packets
    // The signals to end an transactions: xTransDone & xTransSuccess may NOT be used concurrently with the read/write handshake signals!
    input logic fillTransDone,
    input logic fillTransSuccess,
    input logic dataValid,
    input logic [EP_DATA_WID-1:0] dataIn,
    output logic full,

    input logic popTransDone,
    input logic popTransSuccess,
    input logic popData,
    output logic dataAvailable,
    output logic [EP_DATA_WID-1:0] dataOut
);

    logic WEN;
    logic [EP_ADDR_WID-1:0] waddr, raddr;
    logic [EP_DATA_WID-1:0] wdata, rdata;

    bram4k bram(
        .CLK(CLK),
        .WEN(WEN),
        .waddr(waddr),
        .wdata(wdata),
        .raddr(raddr),
        .rdata(rdata)
    );

    FIFO #(
        .ADDR_WID(EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID)
    ) fifo (
        .CLK(CLK),
        .WEN(WEN),
        .waddr(waddr),
        .wdata(wdata),
        .raddr(raddr),
        .rdata(rdata),
        .fillTransDone(fillTransDone),
        .fillTransSuccess(fillTransSuccess),
        .dataValid(dataValid),
        .full(full),
        .dataIn(dataIn),
        .popTransDone(popTransDone),
        .popTransSuccess(popTransSuccess),
        .popData(popData),
        .dataAvailable(dataAvailable),
        .dataOut(dataOut)
    );

endmodule
