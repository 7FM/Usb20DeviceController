`include "config_pkg.sv"
`include "sie_defs_pkg.sv"
`include "usb_packet_pkg.sv"

`include "util_macros.sv"

module usb_rx#()(
    input logic clk12_i,
    input logic rxClk12_i,

    // CRC interface: rxClk12_i
    output logic rxCRCReset_o,
    output logic rxUseCRC16_o,
    output logic rxCRCInput_o,
    output logic rxCRCInputValid_o,
    input logic isValidCRC_i,

    // Bit stuffing interface: rxClk12_i
    output logic rxBitStuffRst_o,
    output logic rxBitStuffData_o,
    input logic expectNonBitStuffedInput_i,
    input logic rxBitStuffError_i,

    // Serial frontend input:
    input logic dataInP_i, // clk48_i
    input logic isValidDPSignal_i, // clk48_i
    input logic eopDetected_i, // clk48_i
    output logic ackEOP_o, // clk12_i

    // Data output interface: synced with clk12_i!
    input logic rxAcceptNewData_i, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte_o, // indicates that the current byte at rxData_o is the last one
    output logic rxDataValid_o, // rxData_o contains valid & new data
    output logic [7:0] rxData_o, // data to be retrieved
    output logic keepPacket_o // should be tested when rxIsLastByte_o set to check whether an retrival error occurred
);

    logic emptyFifo; //TODO how to handle cases when the fifo is empty & we get no data???
    logic dataP_cdc, validSignal_cdc;
    logic dataP, validSignal;
    assign dataP = emptyFifo ? 1'b1 : dataP_cdc;
    assign validSignal = emptyFifo ? 1'b0 : validSignal_cdc;

    ASYNC_FIFO #(
        .ADDR_WID(3),
        .DATA_WID(2),
        .USE_DRAM(1) // Use normal regs as we do not need much data!
    ) bitSyncer(
        .w_clk_i(rxClk12_i),
        .dataValid_i(1'b1),
        .data_i({dataInP_i, isValidDPSignal_i}),
        `MUTE_PIN_CONNECT_EMPTY(full_o),

        .r_clk_i(clk12_i),
        .popData_i(1'b1),
        .empty_o(emptyFifo),
        .data_o({dataP_cdc, validSignal_cdc})
    );

    logic eopDetectedCDC;
    cdc_sync eopDetectSync(
        .clk(clk12_i),
        .in(eopDetected_i),
        .out(eopDetectedCDC)
    );

    logic [7:0] inputBuf;
    logic rxGotNewInput;
    logic gotEopDetect;
    logic dropPacket;
    logic needCRC16Handling;

    usb_rx_interface rx_iface (
        .clk12_i(clk12_i),
        .rxAcceptNewData_i(rxAcceptNewData_i),
        .rxIsLastByte_o(rxIsLastByte_o),
        .rxDataValid_o(rxDataValid_o),
        .rxData_o(rxData_o),
        .keepPacket_o(keepPacket_o),

        // clk12_i signals
        .inputBuf(inputBuf),
        .rxGotNewInput(rxGotNewInput),
        .gotEopDetect(gotEopDetect),
        .dropPacket_i(dropPacket),
        .needCRC16Handling(needCRC16Handling)
    );

    usb_rx_internal rx_internal (
        .clk12_i(clk12_i),

        // CRC interface: clk12_i
        .rxCRCReset_o(rxCRCReset_o),
        .rxUseCRC16_o(rxUseCRC16_o),
        .rxCRCInput_o(rxCRCInput_o),
        .rxCRCInputValid_o(rxCRCInputValid_o),
        .isValidCRC_i(isValidCRC_i),

        // Bit stuffing interface: clk12_i
        .rxBitStuffRst_o(rxBitStuffRst_o),
        .rxBitStuffData_o(rxBitStuffData_o),
        .expectNonBitStuffedInput_i(expectNonBitStuffedInput_i),
        .rxBitStuffError_i(rxBitStuffError_i),

        // Serial frontend input: clk12_i
        .dataInP_i(dataP),
        .isValidDPSignal_i(validSignal),
        .eopDetected_i(eopDetectedCDC),
        .ackEOP_o(ackEOP_o),

        // Rx interface signals
        .inputBuf_o(inputBuf),
        .rxGotNewInput_o(rxGotNewInput),
        .gotEopDetect(gotEopDetect),
        .dropPacket(dropPacket),
        .needCRC16Handling(needCRC16Handling)
    );

endmodule

module usb_rx_interface(
    input logic clk12_i,

    // Data output interface:
    input logic rxAcceptNewData_i, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte_o, // indicates that the current byte at rxData_o is the last one
    output logic rxDataValid_o, // rxData_o contains valid & new data
    output logic [7:0] rxData_o, // data to be retrieved
    output logic keepPacket_o, // should be tested when rxIsLastByte_o set to check whether an retrival error occurred

    // Rx interface signals:
    input logic [7:0] inputBuf,
    input logic rxGotNewInput,
    input logic gotEopDetect,
    input logic dropPacket_i,
    input logic needCRC16Handling
);

//=========================================================================================
//=====================================Interface Start=====================================
//=========================================================================================

    //======================================
    // Start of clk12_i clock domain signals
    //======================================

    logic [3:0] isDataShiftReg, next_isDataShiftReg;

    logic byteWasNotReceived, next_byteWasNotReceived;

    logic rxHandshake;
    assign rxHandshake = rxDataValid_o && rxAcceptNewData_i;

    logic flushBuffersFast, next_flushBuffersFast;
    // Start flushing fast when EOP was detected and stop as soon as the buffers are empty / the last byte at the front -> no more propagations required
    assign next_flushBuffersFast = (flushBuffersFast || gotEopDetect) && |isDataShiftReg[2:0];

    logic rxPropagatePipeline;
    // Propagate the pipeline when inputBufFull is set
    // -> triggers only once!
    // propagate faster (independent from inputBufFull) after we received the EOP signal
    assign rxPropagatePipeline = rxGotNewInput || (flushBuffersFast && (rxHandshake || !rxDataValid_o));

    always_comb begin
        // If there is no more data left then we can clear the flag!
        next_byteWasNotReceived = byteWasNotReceived && (isDataShiftReg[3] || isDataShiftReg[2]);

        // Data output pipeline
        next_isDataShiftReg = isDataShiftReg;

        if (rxPropagatePipeline) begin
            next_isDataShiftReg = {isDataShiftReg[2:0], !flushBuffersFast};

            // If we want to propagate the pipeline and there was still unread data (isData is set & we have no handshake in the same cycle)
            // Then the backend missed reading a byte -> error, we need to drop the entire packet!
            if (!rxHandshake && isDataShiftReg[3]) begin
                next_byteWasNotReceived = 1'b1;
            end
        end else if (rxHandshake) begin
            // If handshake condition is met -> data was read, clear the data signal
            next_isDataShiftReg[3] = 1'b0;
        end

        // Apply patching isData when we received the EndOfPacket signal
        if (gotEopDetect) begin
            if (needCRC16Handling) begin
                // When CRC16 is used then the last two crc bytes in the pipeline are no user data
                // -> the thrid byte in the delay queue is the last byte
                next_isDataShiftReg[1:0] = 2'b0;
            end else begin
                // Else when CRC5 or no CRC at all is used then the first byte in the queue is the last one
                // Also no CRC byte has to be invalidated!
                // -> nothing to do here!
            end
        end

    end

    //===================================================
    // Initialization
    //===================================================
    initial begin
        byteWasNotReceived = 1'b0;
        flushBuffersFast = 1'b0;
        isDataShiftReg = 4'b0;
    end

    always_ff @(posedge clk12_i) begin
        isDataShiftReg <= next_isDataShiftReg;

        byteWasNotReceived <= next_byteWasNotReceived;
        flushBuffersFast <= next_flushBuffersFast;
    end

    logic [7:0] rxQueue [0:3];
    logic [1:0] rxQueueAddr;
    initial begin
        rxQueueAddr = 2'b00;
    end

    always_ff @(posedge clk12_i) begin
        rxQueueAddr <= rxQueueAddr + rxPropagatePipeline;

        if (rxPropagatePipeline) begin
            rxQueue[rxQueueAddr] <= inputBuf;
        end
    end

    // This is the last data byte if this currently is a data byte but the next one is not!
    assign rxIsLastByte_o = isDataShiftReg[3] && !isDataShiftReg[2];
    assign rxDataValid_o = isDataShiftReg[3];
    assign rxData_o = rxQueue[rxQueueAddr];
    assign keepPacket_o = ~(dropPacket_i || byteWasNotReceived);

//=========================================================================================
//======================================Interface End======================================
//=========================================================================================

endmodule

module usb_rx_internal(
    input logic clk12_i,

    // CRC interface:
    output logic rxCRCReset_o,
    output logic rxUseCRC16_o,
    output logic rxCRCInput_o,
    output logic rxCRCInputValid_o,
    input logic isValidCRC_i,

    // Bit stuffing interface:
    output logic rxBitStuffRst_o,
    output logic rxBitStuffData_o,
    input logic expectNonBitStuffedInput_i,
    input logic rxBitStuffError_i,

    // Serial frontend input:
    input logic dataInP_i,
    input logic isValidDPSignal_i,
    input logic eopDetected_i,
    output logic ackEOP_o,

    // Rx interface signals:
    output logic [7:0] inputBuf_o,
    output logic rxGotNewInput_o,
    output logic gotEopDetect,
    output logic dropPacket, // Drop reason might be i.e. receive errors!
    output logic needCRC16Handling
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

    logic nextNeedCRC16Handling;

    // Current signals
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

    assign rxBitStuffData_o = nrziDecodedInput;
    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitStuffRst_o = 1'b0;

    logic isByteData;
    logic isRxWaitForEop;
    logic awaitsPID;
    assign awaitsPID = rxState == RX_GET_PID;
    assign isRxWaitForEop = rxState == RX_WAIT_FOR_EOP;
    assign isByteData = awaitsPID || isRxWaitForEop;

    // Propagate the pipeline when inputBufFull is set
    assign rxGotNewInput_o = (isByteData && inputBufFull);
    assign inputBuf_o = inputBuf;

    // Requires explicit RST to clear eop flag again
    // If waiting for EOP -> we need the detection -> clear RST flag
    assign ackEOP_o = isRxWaitForEop && eopDetected_i;

    //TODO the eopDetected_i signal comes to fast... delay it twice :o
    logic eopDetected_delayed;
    always_ff @(posedge clk12_i) begin
        eopDetected_delayed <= eopDetected_i;
        gotEopDetect <= (gotEopDetect || eopDetected_delayed) && !awaitsPID;
    end

    initial begin
        gotEopDetect = 1'b0;
    end

    // Detections
    logic syncDetect;
    logic gotInvalidDPSignal;

    // Reset signals
    logic rxInputShiftRegReset;
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
    logic defaultNextByteGotSignalError;
    assign defaultNextByteGotSignalError = byteGotSignalError || signalError;

    logic defaultNextDropPacket;
    // Variant which CAN detect missing bit stuffing after CRC edge case: even if this was the last byte, the following bit still needs to statisfy the bit stuffing condition
    assign defaultNextDropPacket = dropPacket || (inputBufFull && (byteGotSignalError || rxBitStuffError_i));
    // Variant which can NOT detect missing bit stuffing after CRC edge case
    //assign defaultNextDropPacket = dropPacket || (inputBufFull && byteGotSignalError);
    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxCRCReset_o = 1'b0;

        next_rxState = rxState;
        nextNeedCRC16Handling = needCRC16Handling;

        // Ensure that the previous dropPacket wont be changed by default!
        next_dropPacket = dropPacket;
        next_byteGotSignalError = defaultNextByteGotSignalError;
        next_lastByteValidCRC = lastByteValidCRC;

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
                    next_byteGotSignalError = 1'b0;
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
                next_dropPacket = defaultNextDropPacket || (gotEopDetect && !lastByteValidCRC);

                if (gotEopDetect) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end else if (inputBufFull) begin
                    // Update is valid crc flag after each byte such that when we receive EOP we can check if the crc was correct for the last byte -> the entire packet!
                    next_lastByteValidCRC = isValidCRC_i;
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
    always_ff @(posedge clk12_i) begin
        rxState <= next_rxState;
        needCRC16Handling <= nextNeedCRC16Handling;
        dropPacket <= next_dropPacket;
        lastByteValidCRC <= next_lastByteValidCRC;
        // After each received byte reset the byte signal error state
        byteGotSignalError <= inputBufFull ? signalError : next_byteGotSignalError;
        // We need to delay isValidDPSignal_i because our nrzi decoder introduces a delay to the decoded signal too
        gotInvalidDPSignal <= !isValidDPSignal_i;
    end

    // Stage 0
    nrzi_decoder nrziDecoder(
        .clk12_i(clk12_i),
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
        .clk12_i(clk12_i),
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
