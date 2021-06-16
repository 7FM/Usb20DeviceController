`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

module usb_rx#()(
    input logic clk48,
    input logic receiveCLK,
    input logic rxRST,

    // CRC interface
    output logic rxCRCReset,
    output logic rxUseCRC16,
    output logic rxCRCInput,
    output logic rxCRCInputValid,
    input logic isValidCRC,

    // Bit stuffing interface
    output logic rxBitStuffRst,
    output logic rxBitStuffData,
    input logic expectNonBitStuffedInput,
    input logic rxBitStuffError,

    // Serial frontend input
    input logic dataInP,
    input logic isValidDPSignal,
    input logic eopDetected,
    output logic ACK_EOP,

    // Data output interface: synced with clk48!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket // should be tested when rxIsLastByte set to check whether an retrival error occurred
);

    typedef enum logic [1:0] {
        RX_WAIT_FOR_SYNC = 0,
        RX_GET_PID,
        RX_WAIT_FOR_EOP,
        RX_RST_DPLL
    } RxStates;

    // Error handling relevant signals
    logic pidValid;

    // State variables
    RxStates rxState;
    logic lastByteValidCRC; // Save current valid CRC flag after each received byte to ensure no difficulties with EOP detection!
    logic dropPacket; // Drop reason might be i.e. receive errors!

    sie_defs_pkg::PID_Types rxPID; //TODO PID is no longer required, only to find out which CRC type is needed! -> store single bit from rxUseCRC16 at correct time!
    logic needCRC16Handling;
    assign needCRC16Handling = rxPID[sie_defs_pkg::PACKET_TYPE_MASK_OFFSET +: sie_defs_pkg::PACKET_TYPE_MASK_LENGTH] == sie_defs_pkg::DATA_PACKET_MASK_VAL; // CRC16 is only used for data packets

    // Current signals
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

    assign rxBitStuffData = nrziDecodedInput;
    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitStuffRst = 1'b0;

//=========================================================================================
//=====================================Interface Start=====================================
//=========================================================================================

    logic [7:0] inputBufRescue, next_inputBufRescue;
    logic [7:0] inputBufDelay1, next_inputBufDelay1;
    logic [7:0] inputBufDelay2, next_inputBufDelay2;
    logic [7:0] next_rxData;
    logic [3:0] isLastShiftReg, next_isLastShiftReg;
    logic [3:0] isDataShiftReg, next_isDataShiftReg;
    assign rxIsLastByte = isLastShiftReg[3];

    logic dataNotYetRead, next_dataNotYetRead;

    logic prev_inputBufFull;
    logic prev_receiveCLK;
    always_ff @(posedge clk48) begin
        prev_inputBufFull <= inputBufFull;
        prev_receiveCLK <= receiveCLK;
    end

    logic rxDataSwapPhase, next_rxDataSwapPhase;

    assign rxDataValid = dataNotYetRead && ~rxDataSwapPhase;

    logic byteWasNotReceived, next_byteWasNotReceived;
    assign keepPacket = ~(dropPacket || byteWasNotReceived);

    always_comb begin
        next_dataNotYetRead = dataNotYetRead;
        next_byteWasNotReceived = byteWasNotReceived;
        next_rxDataSwapPhase = rxDataSwapPhase || (~prev_receiveCLK && ~receiveCLK && prev_inputBufFull);

        if (rxDataValid && rxAcceptNewData) begin
            // If handshake condition is met -> data was read
            next_dataNotYetRead = 1'b0;
        end if (prev_inputBufFull && ~inputBufFull) begin
            // Only execute this on negedge of inputBufFull (synchronized via clk48)
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
        prev_receiveCLK = 1'b0;
        rxDataSwapPhase = 1'b0;
        dataNotYetRead = 1'b0;
        isLastShiftReg = 4'b0;
        isDataShiftReg = 4'b0;
    end

    // Use faster clock domain for the handshaking logic
    always_ff @(posedge clk48) begin
        if (rxRST) begin
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
    assign ACK_EOP = rxEopDetectorReset;
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
    sie_defs_pkg::PID_Types next_rxPID;
    logic next_dropPacket, next_lastByteValidCRC, next_byteGotSignalError;

    logic signalError;
    assign signalError = gotInvalidDPSignal || rxBitStuffError;
    assign next_byteGotSignalError = byteGotSignalError || signalError;

    logic defaultNextDropPacket;
    // Variant which CAN detect missing bit stuffing after CRC edge case: even if this was the last byte, the following bit still needs to statisfy the bit stuffing condition
    assign defaultNextDropPacket = dropPacket || (inputBufFull && (byteGotSignalError || rxBitStuffError));
    // Variant which can NOT detect missing bit stuffing after CRC edge case
    //assign defaultNextDropPacket = dropPacket || (inputBufFull && byteGotSignalError);
    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxEopDetectorReset = 1'b1; // by default reset EOP detection
        rxCRCReset = 1'b0;

        next_rxState = rxState;
        next_rxPID = rxPID;
        next_dropPacket = defaultNextDropPacket;
        next_lastByteValidCRC = lastByteValidCRC;

        // Data output pipeline
        next_inputBufRescue = inputBufFull ? inputBuf : inputBufRescue;
        next_inputBufDelay1 = inputBufFull ? inputBufRescue : inputBufDelay1;
        next_inputBufDelay2 = inputBufFull ? inputBufDelay1 : inputBufDelay2;
        next_rxData = inputBufFull ? inputBufDelay2 : rxData;
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

                // If inputBufFull is set, we already receive the first data bit -> hence crc needs to receive this bit -> but CRC reset low
                rxCRCReset = ~inputBufFull;

                if (inputBufFull) begin
                    // Save the PID for further decisions
                    next_rxPID = inputBuf[3:0];
                    // Go to next state
                    next_rxState = rxStateAdd1;

                    // This byte is data!
                    next_isDataShiftReg[0] = 1'b1;
                end
            end
            RX_WAIT_FOR_EOP: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Sanity check: does the CRC match?
                next_dropPacket = defaultNextDropPacket || (eopDetected && !lastByteValidCRC);

                // We need the EOP detection -> clear RST flag
                rxEopDetectorReset = 1'b0;

                if (eopDetected) begin
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
                    next_lastByteValidCRC = isValidCRC;

                    // This byte is data!
                    next_isDataShiftReg[0] = 1'b1;
                end
            end
            RX_RST_DPLL: begin
                // Go back to the initial state
                next_rxState = RX_WAIT_FOR_SYNC;


                // Trigger some resets
                // TODO is a RST needed for the NRZI decoder?
                rxNRZiDecodeReset = 1'b1;

                // ensure that CRC flag is set to valid again to allow for simple HANDSHAKE packets without payload -> no CRC is used
                next_lastByteValidCRC = 1'b1;
            end
            default: begin
                // Use default values
            end
        endcase
    end

    // State updates
    always_ff @(posedge receiveCLK) begin
        rxState <= next_rxState;
        rxPID <= next_rxPID;
        dropPacket <= next_dropPacket;
        lastByteValidCRC <= next_lastByteValidCRC;
        // After each received byte reset the byte signal error state
        byteGotSignalError <= inputBufFull ? signalError : next_byteGotSignalError;
        // We need to delay isValidDPSignal because our nrzi decoder introduces a delay to the decoded signal too
        gotInvalidDPSignal <= !isValidDPSignal;

        inputBufRescue <= next_inputBufRescue;
        inputBufDelay1 <= next_inputBufDelay1;
        inputBufDelay2 <= next_inputBufDelay2;
        rxData <= next_rxData;
        isLastShiftReg <= next_isLastShiftReg;
        isDataShiftReg <= next_isDataShiftReg;
    end

    // Stage 0
    nrzi_decoder nrziDecoder(
        .clk12(receiveCLK),
        .RST(rxNRZiDecodeReset),
        .data(dataInP),
        .OUT(nrziDecodedInput)
    );

    // Stage 1
    logic _syncDetect;
    sync_detect #(
        .SYNC_VALUE(sie_defs_pkg::SYNC_VALUE)
    ) packetBeginDetector(
        .receivedData(inputBuf[7:4]),
        .SYNC(_syncDetect)
    );
    assign syncDetect = _syncDetect /*&& rxState == RX_WAIT_FOR_SYNC*/;

    input_shift_reg #() inputDeserializer(
        .clk12(receiveCLK),
        .RST(rxInputShiftRegReset),
        .EN(expectNonBitStuffedInput),
        .IN(nrziDecodedInput),
        .dataOut(inputBuf),
        .bufferFull(inputBufFull)
    );

    pid_check #() pidChecker (
        // Order does not matter as the check is actually commutative
        .pidP(inputBuf[7:4]),
        .pidN(inputBuf[3:0]),
        .isValid(pidValid)
    );

    // Needs thight timing -> use input buffer directly
    // Only Data Packets use CRC16!
    // Packet types are identifyable by 2 lsb bits, which are at this stage not yet at the lsb location
    assign rxUseCRC16 = inputBuf[2:1] == sie_defs_pkg::DATA_PACKET_MASK_VAL;
    assign rxCRCInputValid = expectNonBitStuffedInput;
    assign rxCRCInput = nrziDecodedInput;

endmodule
