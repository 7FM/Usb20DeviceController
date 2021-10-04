`include "config_pkg.sv"
`include "sie_defs_pkg.sv"
`include "usb_packet_pkg.sv"

module usb_tx#()(
    input logic clk12_i,

    // CRC interface
    output logic txCRCReset_o,
    output logic txUseCRC16_o,
    output logic txCRCInput_o,
    output logic txCRCInputValid_o,
    input logic [15:0] reversedCRC16_i,

    // Bit stuffing interface
    output logic txBitStuffRst_o,
    output logic txBitStuffDataIn_o,
    input logic txBitStuffDataOut_i,
    input logic txNoBitStuffingNeeded_i,

    // interface inputs
    // Data input interface: synced with clk12_i!
    input logic txReqSendPacket_i, // Trigger sending a new packet

    output logic txAcceptNewData_o, // indicates that the send buffer can be filled
    input logic txIsLastByte_i, // Indicates that the applied txData_i is the last byte to send
    input logic txDataValid_i, // Indicates that txData_i contains valid & new data
    input logic [7:0] txData_i, // Data to be send: First byte should be PID, followed by the user data bytes

    // Serial Frontend
    output logic sending_o, // indicates that currently data is transmitted
    output logic dataOutN_reg_o,
    output logic dataOutP_reg_o
);

    typedef enum logic [3:0] {
        TX_WAIT_SEND_REQ = 0,
        TX_SEND_SYNC,
        TX_SEND_PID,
        TX_SEND_DATA,
        TX_SEND_CRC16_LOWER,
        TX_SEND_CRC16_UPPER,
        TX_EOP_BITSTUFFING_EDGECASE,
        TX_SEND_EOP_1,
        TX_SEND_EOP_2,
        TX_SEND_EOP_3,
        TX_RST_REGS
    } TxStates;

    // State registers: one per line
    usb_packet_pkg::PID_Types txPID, next_txPID;
    TxStates txState, next_txState, txStateAdd1;
    logic sendingLastDataByte, next_sendingLastDataByte;


    initial begin
        dataOutP_reg_o = 1'b1;
        dataOutN_reg_o = 1'b0;
        txState = TX_WAIT_SEND_REQ;
        sending_o = 1'b0;
        sendingLastDataByte = 1'b0;
    end

//=========================================================================================
//=====================================Interface Start=====================================
//=========================================================================================

    logic [7:0] txDataBufNewByte, next_txDataBufNewByte;
    logic txHasDataFetched, next_txHasDataFetched;
    logic txFetchedDataIsLast, next_txFetchedDataIsLast;

    logic waitingForNewSendReq;

    initial begin
        //txPID and txDataBufNewByte are dont cares with the other states
        txHasDataFetched = 1'b1;
        txFetchedDataIsLast = 1'b0;
    end

    assign txAcceptNewData_o = ~txHasDataFetched;

    assign waitingForNewSendReq = txState == TX_WAIT_SEND_REQ;

    logic isResetRegState;
    assign isResetRegState = txState == TX_RST_REGS;

    always_comb begin
        next_txDataBufNewByte = txDataBufNewByte;
        next_txHasDataFetched = txHasDataFetched;
        next_txFetchedDataIsLast = txFetchedDataIsLast;

        // If we have data fetched and new one is required -> clear fetched status as it will be transfered to the shift buffer
        // BUT: this bit may not be cleared if we are waiting for a new write request!
        //      and do not clear while the last byte is sent -> wait for packet to end before starting with new data
        // To avoid a race condition, we should always clear once we switch to sending the SYNC signal
        // Else if we do not have data fetched but the new data is valid -> handshake succeeds -> set fetched status
        // Avoid mutliple clears by only clearing on negedge of txReqNewData
        //next_txHasDataFetched = txHasDataFetched ? txFetchedDataIsLast || ~(!waitingForNewSendReq && prev_txReqNewData && ~txReqNewData) : txDataValid_i;
        next_txHasDataFetched = txHasDataFetched ?
            // Negated clear condition of txHasDataFetched
            // waitingForNewSendReq || (!prev_waitingForNewSendReq && (txFetchedDataIsLast || !prev_txReqNewData || txReqNewData)) :
            // (waitingForNewSendReq && !txReqSendPacket_i) || (!(waitingForNewSendReq && txReqSendPacket_i) && (txFetchedDataIsLast || !txReqNewData))
            (waitingForNewSendReq ? !txReqSendPacket_i : (txFetchedDataIsLast || !txReqNewData))
            // Set condition of txHasDataFetched
            : txDataValid_i;

        // Data handshake condition
        if (txAcceptNewData_o && txDataValid_i) begin
            next_txDataBufNewByte = txData_i;
            next_txFetchedDataIsLast = txIsLastByte_i;
        end else if (sendingLastDataByte) begin
            // During this state the final byte will be sent -> hence we get our final crc value
            next_txDataBufNewByte = crc16[15:8];
        end

        if (isResetRegState) begin
            // Reset important state register: should be the same as in the initial block or after a RST
            next_txFetchedDataIsLast = 1'b0;
        end
    end

    always_ff @(posedge clk12_i) begin
        // Data interface
        txHasDataFetched <= next_txHasDataFetched;
        txFetchedDataIsLast <= next_txFetchedDataIsLast;
        txDataBufNewByte <= next_txDataBufNewByte;
    end

//=========================================================================================
//======================================Interface End======================================
//=========================================================================================

    // Combinatoric logic
    assign txStateAdd1 = txState + 1;

    logic [15:0] crc16;
    logic [4:0] crc5;
    assign crc5 = {reversedCRC16_i[0], reversedCRC16_i[1], reversedCRC16_i[2], reversedCRC16_i[3], reversedCRC16_i[4]};
    assign crc16 = {crc5, reversedCRC16_i[5], reversedCRC16_i[6], reversedCRC16_i[7], reversedCRC16_i[8], reversedCRC16_i[9], reversedCRC16_i[10], reversedCRC16_i[11], reversedCRC16_i[12], reversedCRC16_i[13], reversedCRC16_i[14], reversedCRC16_i[15]};

    //TODO we could make these flags register too and remove txPID -> saves 2 FFs
    logic useCRC16;
    logic noDataAndCrcStage;
    // Only Data Packets use CRC16!
    assign useCRC16 = txPID[usb_packet_pkg::PACKET_TYPE_MASK_OFFSET +: usb_packet_pkg::PACKET_TYPE_MASK_LENGTH] == usb_packet_pkg::DATA_PACKET_MASK_VAL;
    // Either a Handshake or ERR/PRE
    assign noDataAndCrcStage = txPID[usb_packet_pkg::PACKET_TYPE_MASK_OFFSET +: usb_packet_pkg::PACKET_TYPE_MASK_LENGTH] == usb_packet_pkg::HANDSHAKE_PACKET_MASK_VAL || txPID == usb_packet_pkg::PID_SPECIAL_PRE__ERR;

    logic txReqNewData;
    logic txGotNewData;

    logic txNRZiEncodedData;

    logic txSendSingleEnded;
    logic txDataOut;

    logic txRstModules;

    logic [7:0] txDataSerializerIn;
    logic crc5PatchNow;
    logic crc5Patch;

    assign txRstModules = waitingForNewSendReq;

    always_comb begin
        // This could be used to MUX special cases as EOP which should not mess with NRZI encoding
        txDataOut = txNRZiEncodedData;

        // Fallback values
        next_txState = txState;
        next_txPID = txPID;
        txSendSingleEnded = 1'b0;
        txGotNewData = txReqNewData; // Trigger automatically if the buffer gets empty
        txDataSerializerIn = txDataBufNewByte;
        next_sendingLastDataByte = (sendingLastDataByte ^ txReqNewData) && txFetchedDataIsLast;

        crc5Patch = 1'b0;

        if (useCRC16) begin
            if (sendingLastDataByte) begin
                // the final byte is currently sent -> hence we get our final crc value
                // Start sending the lower crc16 byte
                txDataSerializerIn = crc16[7:0];
            end
        end else if (!noDataAndCrcStage && sendingLastDataByte && crc5PatchNow) begin
            // CRC5 needs special treatment as the last data byte has only 3 data bits & the crc is appended!
            // We need to patch the data that will be read as the last byte already contains the crc5!
            //TODO the final CRC5 is calculated while the byte that contains the crc itself is currently send -> we need to patch the shift register content!
            txDataSerializerIn[4:0] = crc5;
            // Mid sending patch...
            txGotNewData = 1'b1;
            crc5Patch = 1'b1;
        end

        // State transitions
        unique case (txState)
            TX_WAIT_SEND_REQ: begin
                // force load SYNC_VALUE to start sending a packet!
                txDataSerializerIn = sie_defs_pkg::SYNC_VALUE;
                txGotNewData = txReqSendPacket_i;

                if (txReqSendPacket_i) begin
                    next_txState = txStateAdd1;
                end
            end
            TX_SEND_SYNC: begin
                // As PID will be sent next, it should be safe to assume that it is currently in txDataBufNewByte or will be set during this time
                next_txPID = txDataBufNewByte[3:0];

                // We can continue after SYNC was sent
                if (txReqNewData) begin
                    next_txState = txStateAdd1;
                end
            end
            TX_SEND_PID: begin
                if (txReqNewData) begin
                    // If there is no data & crc stage then the EOP bit stuffing edge case can not arrise!
                    if (noDataAndCrcStage) begin
                        next_txState = TX_EOP_BITSTUFFING_EDGECASE;
                    end else begin
                        next_txState = txStateAdd1;

                        // Edge case for 0 length data packet -> if this flag is set in this state we can be sure it is crc16 for a data packet
                        if (sendingLastDataByte) begin
                            next_txState = TX_SEND_CRC16_LOWER;
                        end
                    end
                end
            end
            TX_SEND_DATA: begin
                if (txReqNewData) begin
                    // Loop in this state until the last byte will be sent next
                    if (sendingLastDataByte) begin
                        if (useCRC16) begin
                            next_txState = txStateAdd1;
                        end else begin
                            next_txState = TX_EOP_BITSTUFFING_EDGECASE;
                        end
                    end
                end
            end
            TX_SEND_CRC16_LOWER, TX_SEND_CRC16_UPPER: begin
                if (txReqNewData) begin
                    // CRC16 byte 1: Lower crc16 byte was send
                    // CRC5: We can continue after CRC5 with remaining 3 data bits was sent
                    // CRC16 byte 2: the second CRC16 byte was sent (is reused)
                    next_txState = txStateAdd1;
                end
            end
            TX_EOP_BITSTUFFING_EDGECASE: begin
                // Ensure that the last bit is sent as expected

                if (txNoBitStuffingNeeded_i) begin
                    // no bit stuffing -> we can start sending EOP signal next!
                    next_txState = TX_SEND_EOP_1;
                end else begin
                    // We need bit stuffing! -> stay in this state to ensure that the stuffed bit is send too
                end
            end
            TX_SEND_EOP_1, TX_SEND_EOP_2: begin
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
                next_txState = TX_WAIT_SEND_REQ;
            end
        endcase
    end

    // Register updates
    always_ff @(posedge clk12_i) begin
        // State
        txState <= next_txState;
        txPID <= next_txPID;
        sendingLastDataByte <= next_sendingLastDataByte;

        // Output data
        // due to the encoding pipeline, starting and stopping has some latency! and this needs to be accounted for
        // As this is only one stage, we can easily account for the latency by making the 'sending_o' signal a register instead of a wire
        sending_o <= !waitingForNewSendReq && !isResetRegState;
        dataOutP_reg_o <= txDataOut;
        dataOutN_reg_o <= txSendSingleEnded ~^ txDataOut;
    end

    //=======================================================
    //======================= Stage 0 =======================
    //=======================================================

    logic txSerializerOut;
    output_shift_reg #() outputSerializer(
        .clk12_i(clk12_i),
        .en_i(txNoBitStuffingNeeded_i),
        .dataValid_i(txGotNewData),
        .crc5Patch_i(crc5Patch),
        .data_i(txDataSerializerIn),
        .dataBit_o(txSerializerOut),
        .bufferEmpty_o(txReqNewData),
        .crc5PatchNow_o(crc5PatchNow)
    );

    // CRC signals
    assign txCRCReset_o = txState == TX_SEND_PID;
    assign txCRCInputValid_o = txNoBitStuffingNeeded_i;
    assign txCRCInput_o = txSerializerOut;
    assign txUseCRC16_o = useCRC16;

    // Bit stuffing signals
    assign txBitStuffRst_o = txRstModules;
    assign txBitStuffDataIn_o = txSerializerOut;

    //=======================================================
    //======================= Stage 1 =======================
    //=======================================================

    nrzi_encoder nrziEncoder(
        .clk12_i(clk12_i),
        .rst_i(txRstModules),
        .data_i(txBitStuffDataOut_i),
        .data_o(txNRZiEncodedData)
    );

endmodule
