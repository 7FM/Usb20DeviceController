// Detect start of packet signal from input buffer
module sync_detect#()(
    input logic [3:0] receivedData,
    output logic SYNC
);

    // SYNC sequence is KJKJ_KJKK
    // NRZI decoded:    0000_0001
    //              ------ time ---->
    // For robustness we only want to detect the last 4 bits sent: 4b0001 -> as LSb is expected -> 4b1000

    assign SYNC = receivedData == 4'b1000;

endmodule