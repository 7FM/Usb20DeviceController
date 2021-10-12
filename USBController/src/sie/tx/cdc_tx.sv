module cdc_tx(
    input logic clk1,
    input logic txReqSendPacket_i,
    input logic txDataValid_i,
    input logic txIsLastByte_i,
    input logic [7:0] txData_i,
    output logic txAcceptNewData_o,

    input logic clk2,
    output logic txReqSendPacket_o,
    output logic txDataValid_o,
    output logic txIsLastByte_o,
    output logic [7:0] txData_o,
    input logic txAcceptNewData_i
);

    cdc_sync trivialSyncer (
        .clk(clk2),
        .in(txReqSendPacket_i),
        .out(txReqSendPacket_o)
    );
///*
    cdc_2phase_sync #(
        .DATA_WID(8 + 1)
    ) dataSyncer (
        .clk1(clk1),
        .valid_i(txDataValid_i),
        .ready_o(txAcceptNewData_o),
        .data_i({txData_i, txIsLastByte_i}),

        .clk2(clk2),
        .ready_i(txAcceptNewData_i),
        .valid_o(txDataValid_o),
        .data_o({txData_o, txIsLastByte_o})
    );
//*/
/*
    logic fifoFull;
    assign txAcceptNewData_o = !fifoFull;

    logic fifoEmpty;
    assign txDataValid_o = !fifoEmpty;

    ASYNC_FIFO #(
        .ADDR_WID(2),
        .DATA_WID(9),
        .USE_DRAM(1)
    ) cdcFifo (
        .w_clk_i(clk1),
        .dataValid_i(txDataValid_i),
        .data_i({txData_i, txIsLastByte_i}),
        .full_o(fifoFull),

        .r_clk_i(clk2),
        .popData_i(txAcceptNewData_i),
        .empty_o(fifoEmpty),
        .data_o({txData_o, txIsLastByte_o})
    );
*/
endmodule
