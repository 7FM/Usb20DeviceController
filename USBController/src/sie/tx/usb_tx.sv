`include "../../../config.sv"
`include "../sie_common_defs.sv"

module usb_tx#()(
    input logic clk48,
    input logic dataInN,
    input logic dataInP,
    input logic outEN_reg,
    input logic usbResetDetect,
    output logic dataOutN_reg, 
    output logic dataOutP_reg
);

    typedef enum logic[2:0] {
        TX_SEND_SYNC = 0,
        TX_SEND_PID,
        TX_SEND_DATA,
        TX_SEND_CRC5,
        TX_SEND_CRC16,
        TX_SEND_EOP
    } TxStates;

    logic transmitCLK;

    logic txReqNewData; //TODO
    logic txGotNewData; //TODO
    logic [7:0] txSendData; //TODO

    logic txStallDueToBitStuffing; //TODO
    logic txBitStuffedData;
    logic txNRZiEncodedData;

    logic txSendSingleEnded; //TODO
    logic txDataOut;
    initial begin
        dataOutP_reg = 1'b1;
        dataOutN_reg = 1'b0;
    end
    
    always @(posedge transmitCLK) begin
        dataOutP_reg <= txDataOut;
        dataOutN_reg <= txSendSingleEnded ~^ txDataOut;
    end

    //TODO requires special handling for SE0 signals
    // This could be used to MUX special cases as EOP which should not mess with NRZI encoding
    assign txDataOut = txNRZiEncodedData;

    clock_gen #(
        .DIVIDE_LOG_2($clog2(4))
    ) clkDiv4 (
        .inCLK(clk48),
        .outCLK(transmitCLK)
    );

    logic txSerializerOut;
    output_shift_reg #() outputSerializer(
        .clk12(transmitCLK),
        .EN(), //TODO
        .NEW_IN(txGotNewData), //TODO
        .dataIn(txSendData), //TODO
        .OUT(txSerializerOut),
        .bufferEmpty(txReqNewData) //TODO
    );

    usb_bit_stuff txBitStuffing(
        .clk12(transmitCLK),
        .RST(), //TODO
        .data(txSerializerOut),
        .ready(txStallDueToBitStuffing),
        .outData(txBitStuffedData)
    );

    nrzi_encoder nrziEncoder(
        .clk12(transmitCLK),
        .RST(), //TODO
        .data(txBitStuffedData),
        .OUT(txNRZiEncodedData)
    );

endmodule