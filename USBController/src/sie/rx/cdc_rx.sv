module cdc_rx(
    input logic clk1, // Sync in
    output logic rxAcceptNewData_o,
    input logic rxIsLastByte_i,
    input logic rxDataValid_i,
    input logic [7:0] rxData_i,
    input logic keepPacket_i,

    input logic clk2, // Sync out
    input logic rxAcceptNewData_i,
    output logic rxIsLastByte_o,
    output logic rxDataValid_o,
    output logic [7:0] rxData_o,
    output logic keepPacket_o
);

    cdc_2phase_sync #(
        .DATA_WID(8 + 1 + 1)
    ) dataSyncer (
        .clk1(clk1),
        .valid_i(rxDataValid_i),
        .ready_o(rxAcceptNewData_o),
        .data_i({rxData_i, rxIsLastByte_i, keepPacket_i}),

        .clk2(clk2),
        .ready_i(rxAcceptNewData_i),
        .valid_o(rxDataValid_o),
        .data_o({rxData_o, rxIsLastByte_o, keepPacket_o})
    );

endmodule
