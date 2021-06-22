`include "config_pkg.sv"
`include "sie_defs_pkg.sv"
`include "usb_packet_pkg.sv"

module usb_rx#()(
    input logic clk48_i,
    input logic receiveCLK_i,
    input logic rxRST_i,

    // CRC interface
    output logic rxCRCReset_o,
    output logic rxUseCRC16_o,
    output logic rxCRCInput_o,
    output logic rxCRCInputValid_o,
    input logic isValidCRC_i,

    // Bit stuffing interface
    output logic rxBitStuffRst_o,
    output logic rxBitStuffData_o,
    input logic expectNonBitStuffedInput_i,
    input logic rxBitStuffError_i,

    // Serial frontend input
    input logic dataInP_i,
    input logic isValidDPSignal_i,
    input logic eopDetected_i,
    output logic ackEOP_o,

    // Data output interface: synced with clk48_i!
    input logic rxAcceptNewData_i, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte_o, // indicates that the current byte at rxData_o is the last one
    output logic rxDataValid_o, // rxData_o contains valid & new data
    output logic [7:0] rxData_o, // data to be retrieved

    output logic keepPacket_o // should be tested when rxIsLastByte_o set to check whether an retrival error occurred
);

    typedef enum logic [1:0] {
        RX_WAIT_FOR_SYNC = 0,
        RX_GET_PID,
        RX_WAIT_FOR_EOP,
        RX_RST_PHASE
    } RxStates;

    // Error handling relevant signals
    logic pidValid;

    // State variables
    RxStates rxState;
    logic lastByteValidCRC; // Save current valid CRC flag after each received byte to ensure no difficulties with EOP detection!
    logic dropPacket; // Drop reason might be i.e. receive errors!

    logic needCRC16Handling, nextNeedCRC16Handling;

    // Current signals
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

    assign rxBitStuffData_o = nrziDecodedInput;
    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitStuffRst_o = 1'b0;

//=========================================================================================
//=====================================Interface Start=====================================
//=========================================================================================

    //TODO this cascade of registers, likely introduces very very large delays -> another request might already start sending -> DPPL could not be reset!

    logic [7:0] inputBufRescue, next_inputBufRescue;
    logic [7:0] inputBufDelay1, next_inputBufDelay1;
    logic [7:0] inputBufDelay2, next_inputBufDelay2;
    logic [7:0] next_rxData;
    logic [3:0] isLastShiftReg, next_isLastShiftReg;
    logic [3:0] isDataShiftReg, next_isDataShiftReg;
    assign rxIsLastByte_o = isLastShiftReg[3];

    logic dataNotYetRead, next_dataNotYetRead;

    logic prev_inputBufFull;
    logic prev_receiveCLK_i;
    always_ff @(posedge clk48_i) begin
        prev_inputBufFull <= inputBufFull;
        prev_receiveCLK_i <= receiveCLK_i;
    end

    logic rxDataSwapPhase, next_rxDataSwapPhase;

    assign rxDataValid_o = dataNotYetRead && ~rxDataSwapPhase;

    logic byteWasNotReceived, next_byteWasNotReceived;
    assign keepPacket_o = ~(dropPacket || byteWasNotReceived);

    always_comb begin
        next_dataNotYetRead = dataNotYetRead;
        next_byteWasNotReceived = byteWasNotReceived;
        next_rxDataSwapPhase = rxDataSwapPhase || (~prev_receiveCLK_i && ~receiveCLK_i && prev_inputBufFull);

        if (rxDataValid_o && rxAcceptNewData_i) begin
            // If handshake condition is met -> data was read
            next_dataNotYetRead = 1'b0;
        end if (prev_inputBufFull && ~inputBufFull) begin
            // Only execute this on negedge of inputBufFull (synchronized via clk48_i)
            next_rxDataSwapPhase = 1'b0;
            if (isDataShiftReg[3]) begin
                // New data is available
                next_dataNotYetRead = 1'b1;
                // If the previous byte was not yet read but we got a new byte to read -> error data missing
                next_byteWasNotReceived = byteWasNotReceived || dataNotYetRead;
            end
        end
    end

    //===================================================
    // Initialization
    //===================================================
    initial begin
        byteWasNotReceived = 1'b0;
        prev_inputBufFull = 1'b0;
        prev_receiveCLK_i = 1'b0;
        rxDataSwapPhase = 1'b0;
        dataNotYetRead = 1'b0;
        isLastShiftReg = 4'b0;
        isDataShiftReg = 4'b0;
    end

    // Use faster clock domain for the handshaking logic
    always_ff @(posedge clk48_i) begin
        if (rxRST_i) begin
            dataNotYetRead <= 1'b0;
            byteWasNotReceived <= 1'b0;
            rxDataSwapPhase <= 1'b0;
        end else begin
            dataNotYetRead <= next_dataNotYetRead;
            byteWasNotReceived <= next_byteWasNotReceived;
            rxDataSwapPhase <= next_rxDataSwapPhase;
        end
    end

//=========================================================================================
//======================================Interface End======================================
//=========================================================================================

    // Detections
    logic syncDetect;
    logic gotInvalidDPSignal;

    // Reset signals
    logic rxInputShiftRegReset;

    logic rxEopDetectorReset; // Requires explicit RST to clear eop flag again
    assign ackEOP_o = rxEopDetectorReset;
    logic rxNRZiDecodeReset;
    logic byteGotSignalError;


    //===================================================
    // Initialization
    //===================================================
    initial begin
        rxState = RX_WAIT_FOR_SYNC;
        dropPacket = 1'b0;
        byteGotSignalError = 1'b0;
        lastByteValidCRC = 1'b1;
    end

    //===================================================
    // State transitions
    //===================================================
    RxStates next_rxState, rxStateAdd1;
    logic next_dropPacket, next_lastByteValidCRC, next_byteGotSignalError;

    logic signalError;
    assign signalError = gotInvalidDPSignal || rxBitStuffError_i;
    assign next_byteGotSignalError = byteGotSignalError || signalError;

    logic defaultNextDropPacket;
    // Variant which CAN detect missing bit stuffing after CRC edge case: even if this was the last byte, the following bit still needs to statisfy the bit stuffing condition
    assign defaultNextDropPacket = dropPacket || (inputBufFull && (byteGotSignalError || rxBitStuffError_i));
    // Variant which can NOT detect missing bit stuffing after CRC edge case
    //assign defaultNextDropPacket = dropPacket || (inputBufFull && byteGotSignalError);
    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxEopDetectorReset = 1'b1; // by default reset EOP detection
        rxCRCReset_o = 1'b0;

        next_rxState = rxState;
        nextNeedCRC16Handling = needCRC16Handling;
        next_dropPacket = defaultNextDropPacket;
        next_lastByteValidCRC = lastByteValidCRC;

        // Data output pipeline
        next_inputBufRescue = inputBufFull ? inputBuf : inputBufRescue;
        next_inputBufDelay1 = inputBufFull ? inputBufRescue : inputBufDelay1;
        next_inputBufDelay2 = inputBufFull ? inputBufDelay1 : inputBufDelay2;
        next_rxData = inputBufFull ? inputBufDelay2 : rxData_o;
        next_isLastShiftReg = inputBufFull ? {isLastShiftReg[2:0], 1'b0} : isLastShiftReg;
        next_isDataShiftReg = inputBufFull ? {isDataShiftReg[2:0], 1'b0} : isDataShiftReg;

        unique case (rxState)
            RX_WAIT_FOR_SYNC: begin
                // Ensure that the previous dropPacket wont be changed until we receive a new packet!
                next_dropPacket = dropPacket;

                if (syncDetect) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                    //TODO trigger required resets right before payload data arrives
                    // Input shift register needs valid counter reset to be aligned with the incoming packet content
                    rxInputShiftRegReset = 1'b1;

                    // reset drop state
                    next_dropPacket = 1'b0;
                end
            end
            RX_GET_PID: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Also there may not be invalid differential pair signals as we expect the PID to be send!
                // Sanity check: was PID correctly received?
                next_dropPacket = defaultNextDropPacket || (inputBufFull && !pidValid);

                if (inputBufFull) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;

                    // This byte is data!
                    next_isDataShiftReg[0] = 1'b1;
                end else begin
                    // If inputBufFull is set, we already receive the first data bit -> hence crc needs to receive this bit -> but CRC reset low
                    rxCRCReset_o = 1'b1;
                    // As during CRC reset the rxUseCRC16_o flag is evaluated we can use it for our purposes too
                    nextNeedCRC16Handling = rxUseCRC16_o;
                end
            end
            RX_WAIT_FOR_EOP: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Sanity check: does the CRC match?
                next_dropPacket = defaultNextDropPacket || (eopDetected_i && !lastByteValidCRC);

                // We need the EOP detection -> clear RST flag
                rxEopDetectorReset = 1'b0;

                if (eopDetected_i) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                    if (needCRC16Handling) begin
                        // When CRC16 is used then the last two crc bytes in the pipeline are no user data
                        next_isDataShiftReg[1:0] = 2'b0;
                        // Also the thrid byte in the delay queue is the last byte
                        next_isLastShiftReg[2] = 1'b1;
                    end else begin
                        // Else when CRC5 or no CRC at all is used then the first byte in the queue is the last one
                        // Also no CRC byte has to be invalidated!
                        next_isLastShiftReg[0] = 1'b1;
                    end
                end else if (inputBufFull) begin
                    next_lastByteValidCRC = isValidCRC_i;

                    // This byte is data!
                    next_isDataShiftReg[0] = 1'b1;
                end
            end
            RX_RST_PHASE: begin
                // Go back to the initial state
                next_rxState = RX_WAIT_FOR_SYNC;


                // Trigger some resets
                // TODO is a RST needed for the NRZI decoder?
                rxNRZiDecodeReset = 1'b1;

                // ensure that CRC flag is set to valid again to allow for simple HANDSHAKE packets without payload -> no CRC is used
                next_lastByteValidCRC = 1'b1;
            end
        endcase
    end

    // State updates
    always_ff @(posedge receiveCLK_i) begin
        rxState <= next_rxState;
        needCRC16Handling <= nextNeedCRC16Handling;
        dropPacket <= next_dropPacket;
        lastByteValidCRC <= next_lastByteValidCRC;
        // After each received byte reset the byte signal error state
        byteGotSignalError <= inputBufFull ? signalError : next_byteGotSignalError;
        // We need to delay isValidDPSignal_i because our nrzi decoder introduces a delay to the decoded signal too
        gotInvalidDPSignal <= !isValidDPSignal_i;

        inputBufRescue <= next_inputBufRescue;
        inputBufDelay1 <= next_inputBufDelay1;
        inputBufDelay2 <= next_inputBufDelay2;
        rxData_o <= next_rxData;
        isLastShiftReg <= next_isLastShiftReg;
        isDataShiftReg <= next_isDataShiftReg;
    end

    // Stage 0
    nrzi_decoder nrziDecoder(
        .clk12_i(receiveCLK_i),
        .rst_i(rxNRZiDecodeReset),
        .data_i(dataInP_i),
        .data_o(nrziDecodedInput)
    );

    // Stage 1
    logic _syncDetect;
    sync_detect #(
        .SYNC_VALUE(sie_defs_pkg::SYNC_VALUE)
    ) packetBeginDetector(
        .receivedData_i(inputBuf[7:4]),
        .syncDetect_o(_syncDetect)
    );
    assign syncDetect = _syncDetect /*&& rxState == RX_WAIT_FOR_SYNC*/;

    input_shift_reg #() inputDeserializer(
        .clk12_i(receiveCLK_i),
        .rst_i(rxInputShiftRegReset),
        .en_i(expectNonBitStuffedInput_i),
        .dataBit_i(nrziDecodedInput),
        .data_o(inputBuf),
        .bufferFull_o(inputBufFull)
    );

    pid_check #() pidChecker (
        // Order does not matter as the check is actually commutative
        .pidP_i(inputBuf[7:4]),
        .pidN_i(inputBuf[3:0]),
        .isValid_o(pidValid)
    );

    // Needs thight timing -> use input buffer directly
    // Only Data Packets use CRC16!
    // Packet types are identifyable by 2 lsb bits, which are at this stage not yet at the lsb location
    assign rxUseCRC16_o = inputBuf[2:1] == usb_packet_pkg::DATA_PACKET_MASK_VAL;
    assign rxCRCInputValid_o = expectNonBitStuffedInput_i;
    assign rxCRCInput_o = nrziDecodedInput;

endmodule
