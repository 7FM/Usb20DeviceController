// Detect start of packet signal from input buffer
module sync_detect#(
    parameter SYNC_VALUE
)(
    input logic [3:0] receivedData_i,
    output logic syncDetect_o
);

    // SYNC sequence is KJKJ_KJKK
    // NRZI decoded:    0000_0001
    //              ------ time ---->
    // For robustness we only want to detect the last 4 bits sent: 4b0001 -> as LSb is expected -> 4b1000
    assign syncDetect_o = receivedData_i == SYNC_VALUE[7:4];

endmodule
