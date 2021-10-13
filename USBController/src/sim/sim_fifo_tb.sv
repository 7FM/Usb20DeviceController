module sim_fifo_tb (
    input logic CLK,

    // Provide transactional read & write behaviour to allow reseting the values on failures without overwriting/loosing i.e. not yet send data or discarding corrupt packets
    // The signals to end an transactions: xTransDone & xTransSuccess may NOT be used concurrently with the read/write handshake signals!
    input logic fillTransDone_i,
    input logic fillTransSuccess_i,
    input logic dataValid_i,
    input logic [EP_DATA_WID-1:0] data_i,
    output logic full_o,

    input logic popTransDone_i,
    input logic popTransSuccess_i,
    input logic popData_i,
    output logic dataAvailable_o,
    output logic [EP_DATA_WID-1:0] data_o
);

    localparam EP_ADDR_WID = 9;
    localparam EP_DATA_WID = 8;

    BRAM_FIFO #(
        .ADDR_WID(EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID),
        // .ENTRIES(2**EP_ADDR_WID)
        .ENTRIES(502)
    ) fifo2n (
        .clk_i(CLK),

        .fillTransDone_i(fillTransDone_i),
        .fillTransSuccess_i(fillTransSuccess_i),
        .dataValid_i(dataValid_i),
        .data_i(data_i),
        .full_o(full_o),

        .popTransDone_i(popTransDone_i),
        .popTransSuccess_i(popTransSuccess_i),
        .popData_i(popData_i),
        .dataAvailable_o(dataAvailable_o),
        .data_o(data_o)
    );


endmodule
