`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

module usb_tx#()(
    input logic clk48,
    input logic usbResetDetect, //TODO how to handle this signal? Is it even relevant during sending phase? I honestly do not think so

    // interface inputs
    //TODO currently this interface uses the slower tx clk12 domain... -> client needs to ensure that txAcceptNewData is not interpret multiple times as true without low phase
    input logic reqSendPacket, // Trigger sending a new packet

    output logic txAcceptNewData, // indicates that the send buffer can be filled
    input logic txIsLastByte, // Indicates that the applied txData is the last byte to send
    input logic txDataValid, // Indicates that txData contains valid & new data
    input logic [7:0] txData, // Data to be send: First byte should be PID, followed by the user data bytes

    output logic sending, // indicates that currently data is transmitted

    // Data out
    output logic dataOutN_reg,
    output logic dataOutP_reg
);

    typedef enum logic [3:0] {
        TX_WAIT_SEND_REQ = 0,
        TX_SEND_SYNC,
        TX_SEND_PID,
        TX_SEND_DATA,
        TX_SEND_DATA_CRC16_TRANSITION,
        TX_SEND_CRC16,
        TX_SEND_CRC5,
        TX_SEND_EOP_1,
        TX_SEND_EOP_2,
        TX_SEND_EOP_3,
        TX_RST_REGS
    } TxStates;

    logic transmitCLK;

    // State registers: one per line
    sie_defs_pkg::PID_Types txPID, next_txPID;
    TxStates txState, next_txState, txStateAdd1;
    logic [7:0] txtxData, txtxDataNewByte, next_txtxDataNewByte;
    logic txHasDataFetched, next_txHasDataFetched;
    logic txFetchedDataIsLast, next_txFetchedDataIsLast;

    initial begin
        dataOutP_reg = 1'b1;
        dataOutN_reg = 1'b0;

        //txPID and txtxDataNewByte are dont cares with the other states
        txState = TX_WAIT_SEND_REQ;
        txHasDataFetched = 1'b0;
        txFetchedDataIsLast = 1'b0;
    end

    // Combinatoric logic
    assign txStateAdd1 = txState + 1;
    logic [15:0] reversedCRC16, crc16; 
    logic [4:0] crc5;
    logic useCRC16;
    logic noDataAndCrcStage;

    // Only Data Packets use CRC16!
    assign useCRC16 = txPID[1:0] == sie_defs_pkg::PID_DATA0[1:0];
    // Either a Handshake or ERR/PRE
    assign noDataAndCrcStage = txPID[1:0] == sie_defs_pkg::PID_HANDSHAKE_ACK[1:0] || txPID == sie_defs_pkg::PID_SPECIAL_PRE__ERR;
    assign crc16 = {reversedCRC16[0], reversedCRC16[1], reversedCRC16[2], reversedCRC16[3], reversedCRC16[4], reversedCRC16[5], reversedCRC16[6], reversedCRC16[7], reversedCRC16[8], reversedCRC16[9], reversedCRC16[10], reversedCRC16[11], reversedCRC16[12], reversedCRC16[13], reversedCRC16[14], reversedCRC16[15]};
    assign crc5 = {reversedCRC16[0], reversedCRC16[1], reversedCRC16[2], reversedCRC16[3], reversedCRC16[4]};

    logic txReqNewData;
    logic txGotNewData;

    assign txAcceptNewData = ~txHasDataFetched;

    logic txNRZiEncodedData;

    logic txSendSingleEnded;
    logic txDataOut;

    logic txRstModules;

    localparam TX_INIT_LATENCY = 4'd2;  //TODO due to the encoding pipeline, starting and stopping has some latency! and this needs to be accounted for
    assign sending = txState > TX_WAIT_SEND_REQ + TX_INIT_LATENCY;
    assign txRstModules = txState == TX_WAIT_SEND_REQ;

    always_comb begin
        // This could be used to MUX special cases as EOP which should not mess with NRZI encoding
        txDataOut = txNRZiEncodedData;

        // Fallback values
        next_txState = txState;
        next_txPID = txPID;
        txSendSingleEnded = 1'b0;
        txGotNewData = txReqNewData; // Trigger automatically if the buffer gets empty
        txtxData = txtxDataNewByte;

        next_txtxDataNewByte = txtxDataNewByte;
        next_txHasDataFetched = txHasDataFetched;
        next_txFetchedDataIsLast = txFetchedDataIsLast;

        // If we have data fetched and new one is required -> clear fetched status as it will be transfered to the shift buffer
        // BUT: this bit may not be cleared if we are waiting for a new write request! and do not clear when the last byte was send -> wait for packet to end before starting with new data
        // Else if we do not have data fetched but the new data is valid -> handshake succeeds -> set fetched status
        next_txHasDataFetched = txHasDataFetched ? txFetchedDataIsLast || ~(txState > TX_WAIT_SEND_REQ && txReqNewData) : txDataValid;

        // Data handshake condition
        if (txAcceptNewData && txDataValid) begin
            //next_txHasDataFetched = 1'b1;
            next_txtxDataNewByte = txData;
            next_txFetchedDataIsLast = txIsLastByte;
        end
    
        // State transitions
        unique case (txState)
            TX_WAIT_SEND_REQ: begin
                txtxData = sie_defs_pkg::SYNC_VALUE;
                // force load SYNC_VALUE to start sending a packet!
                txGotNewData = reqSendPacket;
                if (reqSendPacket) begin
                    next_txState = txStateAdd1;
                end
            end
            TX_SEND_SYNC: begin
                // As PID will be sent next, it should be safe to assume that it is currently in txtxDataNewByte or will be set during this time
                next_txPID = txtxDataNewByte[3:0];

                // We can continue after SYNC was sent
                if (txReqNewData) begin
                    next_txState = txStateAdd1;
                end
            end
            TX_SEND_PID: begin
                if (txReqNewData) begin
                    next_txState = noDataAndCrcStage? TX_SEND_EOP_1 : txStateAdd1;
                    //TODO set send data for EOP to work!
                end
            end
            TX_SEND_DATA: begin
                if (txReqNewData) begin
                    // Loop in this state until the last byte will be sent next
                    if (txFetchedDataIsLast) begin
                        if (useCRC16) begin
                            next_txState = txStateAdd1;
                        end else begin
                            // CRC5 needs special treatment as it needs 3 data bits
                            // We need to patch the data that will be read as the last byte already contains the crc5!
                            txtxData = {crc5, txtxDataNewByte[2:0]};
                            next_txState = TX_SEND_CRC5;
                        end
                    end
                end
            end
            TX_SEND_DATA_CRC16_TRANSITION: begin
                // During this state the final byte will be sent -> hence we get our final crc value
                next_txtxDataNewByte = crc16[15:8];
                // Start sending the lower crc16 byte
                txtxData = crc16[7:0];

                if (txReqNewData) begin
                    next_txState = txStateAdd1;
                end
            end
            TX_SEND_CRC16: begin
                if (txReqNewData) begin
                    // Lower crc16 byte was send
                    next_txState = txStateAdd1;
                    // Finally also send the second crc16 byte
                    //txtxData = txtxDataNewByte;
                end
            end
            TX_SEND_CRC5: begin
                // We can continue after CRC5 with remaining 3 data bits was sent OR the second CRC16 byte was sent (is reused)
                if (txReqNewData) begin
                    next_txState = txStateAdd1;
                    //TODO set send data for EOP to work!
                end
            end
            TX_SEND_EOP_1, TX_SEND_EOP_2: begin
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!
                //TODO we need to handle the edge case where a zero bit is stuffed right before the EOP signal!!!

                // special handling for SE0 signals
                txDataOut = 1'b0;
                txSendSingleEnded = 1'b1;

                next_txState = txStateAdd1;
            end
            TX_SEND_EOP_3: begin
                txDataOut = 1'b1;
                next_txState = txStateAdd1;
            end
            TX_RST_REGS: begin
                // Reset important state register: should be same as after a RST or in the initial block
                next_txFetchedDataIsLast = 1'b0;
                next_txHasDataFetched = 1'b0;
                next_txState = TX_WAIT_SEND_REQ;
            end
            default: begin

            end
        endcase
    end

    // Register updates
    always_ff @(posedge transmitCLK) begin
        // State
        txState <= next_txState;
        txPID <= next_txPID;

        // Data interface
        txHasDataFetched <= next_txHasDataFetched;
        txFetchedDataIsLast <= next_txFetchedDataIsLast;
        txtxDataNewByte <= next_txtxDataNewByte;

        // Output data
        dataOutP_reg <= txDataOut;
        dataOutN_reg <= txSendSingleEnded ~^ txDataOut;
    end

    clock_gen #(
        .DIVIDE_LOG_2($clog2(4))
    ) clkDiv4 (
        .inCLK(clk48),
        .outCLK(transmitCLK)
    );

    //=======================================================
    //======================= Stage 0 =======================
    //=======================================================

    logic txNoBitStuffingNeeded;
    logic txSerializerOut;
    output_shift_reg #() outputSerializer(
        .clk12(transmitCLK),
        .EN(txNoBitStuffingNeeded),
        .NEW_IN(txGotNewData),
        .dataIn(txtxData),
        .OUT(txSerializerOut),
        .bufferEmpty(txReqNewData)
    );


    usb_crc crcEngine (
        .clk12(transmitCLK),
        //TODO we need to exclude undesired fields too: might be controlled with the rst signal
        //TODO for rx logic state comparison as reset signal was to delayed! -> likely needs to be set in state transition logic
        //TODO for rx logic state comparison as reset signal was to delayed! -> likely needs to be set in state transition logic
        //TODO for rx logic state comparison as reset signal was to delayed! -> likely needs to be set in state transition logic
        //TODO for rx logic state comparison as reset signal was to delayed! -> likely needs to be set in state transition logic
        //TODO for rx logic state comparison as reset signal was to delayed! -> likely needs to be set in state transition logic
        //TODO for rx logic state comparison as reset signal was to delayed! -> likely needs to be set in state transition logic
        .RST(txState == TX_SEND_PID), // Required at every new packet, can be a wire
        .VALID(txNoBitStuffingNeeded), // Indicates if current data is valid(no bit stuffing) and used for the CRC. Can be a wire
        .rxUseCRC16(useCRC16),
        .data(txSerializerOut),
        .crc(reversedCRC16),
        .validCRC() // This pin is unused for tx purposes
    );

    logic txBitStuffedData;
    usb_bit_stuff txBitStuffing(
        .clk12(transmitCLK),
        .RST(txRstModules),
        .data(txSerializerOut),
        .ready(txNoBitStuffingNeeded),
        .outData(txBitStuffedData)
    );

    //=======================================================
    //======================= Stage 1 =======================
    //=======================================================

    nrzi_encoder nrziEncoder(
        .clk12(transmitCLK),
        .RST(txRstModules),
        .data(txBitStuffedData),
        .OUT(txNRZiEncodedData)
    );

endmodule
