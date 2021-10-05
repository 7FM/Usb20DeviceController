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

    //TODO this will change to two clocks of the same speed but with different phases!
    //TODO -> it would be the best to use a minimal 2 phase sync here to to avoid any clock requirements!
    //TODO sync txReqSendPacket from faster clk1 to slower clk2
    logic stretchedReq;
    logic [1:0] cnt;
    initial begin
        stretchedReq = 1'b0;
    end
    always_ff @(posedge clk1) begin
        if (txReqSendPacket_i) begin
            cnt <= 0;
            stretchedReq <= 1'b1;
        end else if (stretchedReq) begin
            cnt <= cnt + 1;
            stretchedReq <= !(&cnt);
        end
    end
    cdc_sync trivialSyncer (
        .clk(clk2),
        .in(stretchedReq),
        .out(txReqSendPacket_o)
    );

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

endmodule
