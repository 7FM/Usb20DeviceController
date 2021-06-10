`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

module usb_rx#()(
    input logic clk48,
    input logic receiveCLK,

    input logic dataInP,
    input logic dataInN,
    input logic outEN_reg,
    input logic ACK_USB_RST,
    output logic usbResetDetect,

    // Data output interface: synced with clk48!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket // should be tested when rxIsLastByte set to check whether an retrival error occurred

`ifdef USE_DEBUG_LEDS
    ,output logic LED_R,
    output logic LED_G,
    output logic LED_B
`endif
);

    typedef enum logic [1:0] {
        RX_WAIT_FOR_SYNC = 0,
        RX_GET_PID,
        RX_WAIT_FOR_EOP,
        RX_RST_DPLL
    } RxStates;

    // TODO errror handling
    // Error handling relevant signals
    logic receiveBitStuffingError;
    logic pidValid;
    logic isValidCRC;

    logic isValidDPSignal;

    assign isValidDPSignal = dataInN ^ dataInP;

    // State variables
    RxStates rxState;
    sie_defs_pkg::PID_Types rxPID;
    logic lastByteValidCRC; // Save current valid CRC flag after each received byte to ensure no difficulties with EOP detection!
    logic dropPacket; // Drop reason might be i.e. receive errors!

    // Current signals
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

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

    logic dataNotYetRead, next_dataNotYetRead; //TODO check handshake & update accordingly!

    assign rxDataValid = dataNotYetRead;

    //TODO keepPacket

    logic [1:0] inputBufFull_clk48_sync;
    always_ff @(posedge receiveCLK) begin
        inputBufFull_clk48_sync <= {inputBufFull, inputBufFull_clk48_sync[1]};
    end

    logic byteWasNotReceived, next_byteWasNotReceived;
    assign keepPacket = ~(dropPacket || byteWasNotReceived);

    always_comb begin
        next_dataNotYetRead = dataNotYetRead;
        next_byteWasNotReceived = byteWasNotReceived;

        if (rxDataValid) begin
            // If handshake condition is met -> data was read
            next_dataNotYetRead = ~rxAcceptNewData;
        end else if (~inputBufFull_clk48_sync[0] && inputBufFull_clk48_sync[1]) begin
            // Only execute this on posedge of inputBufFull (synchronized via receiveCLK)
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
        inputBufFull_clk48_sync = 2'b0;
        dataNotYetRead = 1'b0;
        isLastShiftReg = 4'b0;
        isDataShiftReg = 4'b0;
    end

    // Use faster clock domain for the handshaking logic
    always_ff @(posedge clk48) begin
        if (outEN_reg) begin
            dataNotYetRead <= 1'b0;
            byteWasNotReceived <= 1'b0;
        end else begin
            dataNotYetRead <= next_dataNotYetRead;
            byteWasNotReceived <= next_byteWasNotReceived;
        end
    end

    logic needCRC16Handling;
    assign needCRC16Handling = rxPID[1:0] == 2'b11; // CRC16 is only used for data packets

//=========================================================================================
//======================================Interface End======================================
//=========================================================================================

    // Detections
    logic nonBitStuffedInput;
    logic eopDetected;
    logic syncDetect;

    // Reset signals
    logic rxInputShiftRegReset;

    logic rxEopDetectorReset; // Requires explicit RST to clear eop flag again
    logic rxBitUnstuffingReset;
    logic rxNRZiDecodeReset;
    logic rxCRCReset;


`ifdef USE_DEBUG_LEDS
    initial begin
        LED_R = 1'b0;
        LED_G = 1'b0;
        LED_B = 1'b0;
    end

    always_ff @(posedge clk48) begin
        // Do not reset values once target signal value was achieved
        LED_R <= LED_R || dropPacket;
        LED_B <= LED_B || usbResetDetect;
    end
`endif

    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitUnstuffingReset = 1'b0;


    //===================================================
    // Initialization
    //===================================================
    initial begin
        rxState = RX_WAIT_FOR_SYNC;
        dropPacket = 1'b0;
        lastByteValidCRC = 1'b1;
    end

    //===================================================
    // State transitions
    //===================================================
    RxStates next_rxState, rxStateAdd1;
    sie_defs_pkg::PID_Types next_rxPID;
    logic next_dropPacket, next_lastByteValidCRC;

    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxEopDetectorReset = 1'b1; // by default reset EOP detection
        rxCRCReset = 1'b0;

        next_rxState = rxState;
        next_rxPID = rxPID;
        next_dropPacket = dropPacket;
        next_lastByteValidCRC = lastByteValidCRC;

        // Data output pipeline
        next_inputBufRescue = inputBufFull ? inputBuf : inputBufRescue;
        next_inputBufDelay1 = inputBufFull ? inputBufRescue : inputBufDelay1;
        next_inputBufDelay2 = inputBufFull ? inputBufDelay1 : inputBufDelay2;
        next_rxData = inputBufFull ? inputBufDelay2 : rxData;
        next_isLastShiftReg = inputBufFull ? {isLastShiftReg[2:0], 1'b0} : isLastShiftReg; //TODO needs to be patched on EOP detect!
        next_isDataShiftReg = inputBufFull ? {isDataShiftReg[2:0], 1'b0} : isDataShiftReg; //TODO needs to be patched if current byte is data

        unique case (rxState)
            RX_WAIT_FOR_SYNC: begin
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
                next_dropPacket = dropPacket || receiveBitStuffingError || !isValidDPSignal || (inputBufFull && !pidValid);

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
                //TODO would be nice to integrate some isValidDPSignal checks, but this might break logic very very easily!

                // After Sync was detected, we always need valid bit stuffing!
                // Sanity check: does the CRC match?
                next_dropPacket = dropPacket || receiveBitStuffingError || (eopDetected && !lastByteValidCRC);

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
                    //TODO further processing is required! i.e. give data to next stage for processing
                    //TODO we probably do not want to give the crc data to the next stage how can we do so? just assume that the backend will ignore it?

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

        inputBufRescue <= next_inputBufRescue;
        inputBufDelay1 <= next_inputBufDelay1;
        inputBufDelay2 <= next_inputBufDelay2;
        rxData <= next_rxData;
        isLastShiftReg <= next_isLastShiftReg;
        isDataShiftReg <= next_isDataShiftReg;
    end

    eop_reset_detect eopAndResetDetect(
        .clk48(clk48),
        .RST(rxEopDetectorReset),
        .dataInP(dataInP),
        .dataInN(dataInN),
        .eop(eopDetected),
        .usb_reset(usbResetDetect),
        .ACK_USB_RST(ACK_USB_RST)
    );

    nrzi_decoder nrziDecoder(
        .clk12(receiveCLK),
        .RST(rxNRZiDecodeReset),
        .data(dataInP),
        .OUT(nrziDecodedInput)
    );

    //TODO reuse
    usb_bit_unstuff receiveBitUnstuffing(
        .clk12(receiveCLK),
        .RST(rxBitUnstuffingReset),
        .data(nrziDecodedInput),
        .valid(nonBitStuffedInput),
        .error(receiveBitStuffingError)
    );

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
        .EN(nonBitStuffedInput),
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

    logic useCRC5;
    // Needs thight timing -> use input buffer directly
    // CRC5 is only used for token packets -> identified by 2 lsb bits, which are at this stage not yet at the lsb location
    assign useCRC5 = inputBuf[2:1] == 2'b01;

    //TODO reuse
    usb_crc crcEngine (
        .clk12(receiveCLK),
        .RST(rxCRCReset), // Required at every new packet, can be a wire
        //TODO we need to exclude undesired fields too: this might already work as PID fields are excluded by design of the RST signal being high during PID reception
        .VALID(nonBitStuffedInput), // Indicates if current data is valid(no bit stuffing) and used for the CRC. Can be a wire
        .crc5_or_16(useCRC5), // Indicate which CRC should type should be calculated/checked, needs to be set when RST is set high
        .data(nrziDecodedInput),
        .validCRC(isValidCRC),
        .crc() //TODO only needed for transmission also ensure that it will be send in revere order (MSb first)!
    );

endmodule
