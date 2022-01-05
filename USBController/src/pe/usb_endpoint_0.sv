`include "usb_ep_pkg.sv"
`include "usb_desc_pkg.sv"
`include "usb_dev_req_pkg.sv"
`include "usb_packet_pkg.sv"

// AKA control endpoint with address 0
module usb_endpoint_0 #(
    parameter USB_DEV_ADDR_WID = 7,
    parameter USB_DEV_CONF_WID = 8,
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF
)(
    input logic clk12_i,

    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,
    output logic [USB_DEV_ADDR_WID-1:0] deviceAddr_o,
    output logic [USB_DEV_CONF_WID-1:0] deviceConf_o,
    output logic resetDataToggle_o,

    input logic gotTransStartPacket_i,
    input logic [1:0] transStartTokenID_i,
    // Status bit that indicated whether the next byte is the PID or actual data
    // This information can be simply obtained by watching gotTransStartPacket_i
    // but as this is likely needed for IN endpoints, the logic was centralized
    // to safe resources!
    input logic byteIsData_i,

    // Device IN interface
    input logic EP_IN_fillTransDone_i,
    input logic EP_IN_fillTransSuccess_i,
    input logic EP_IN_dataValid_i,
    input logic [7:0] EP_IN_data_i,
    output logic EP_IN_full_o,

    /*
    input logic EP_IN_popTransDone_i,
    input logic EP_IN_popTransSuccess_i,
    input logic EP_IN_popData_i,
    output logic EP_IN_dataAvailable_o,
    output logic [7:0] EP_IN_data_o,
    */

    // Device OUT interface
    /*
    input logic EP_OUT_fillTransDone_i,
    input logic EP_OUT_fillTransSuccess_i,
    input logic EP_OUT_dataValid_i,
    input logic [7:0] EP_OUT_data_i,
    output logic EP_OUT_full_o,
    */

    input logic EP_OUT_popTransDone_i,
    input logic EP_OUT_popTransSuccess_i,
    input logic EP_OUT_popData_i,
    output logic EP_OUT_dataAvailable_o,
    output logic EP_OUT_isLastPacketByte_o,
    output logic [7:0] EP_OUT_data_o,

    // Let usb_pe handle sending the PID, to save identical logic in each endpoint!
    // Also the usb_pe handle the maxPacketSize logic!
    // Signal that EP is ready to send a response
    output logic respValid_o,
    // Either data out phase or status out phase
    // Specify if the given pid ID should be interpret as DATA pid or handshake
    // If it is a handshake then no data will be popped and sent!
    // Else data will automatically be popped afterwards!
    output logic respHandshakePID_o,
    output logic [1:0] respPacketID_o
);

    usb_dev_req_pkg::SetupDataPacket setupDataPacket;

    //===============================================================================================================
    // Device State

    //logic suspended; // Currently not supported / considered
    typedef enum logic[1:0] {
        DEVICE_NOT_RESET = 0, // Ignore all transactions except reset signal //TODO?
        DEVICE_RESET, // Responds to device and configuration descriptor requests & return information, uses default address
        DEVICE_ADDR_ASSIGNED, // responds to requests to default control pipe with default address as long as no address was assigned
        DEVICE_CONFIGURED // processed a SetConfiguration() request with non zero configuration value & endpoints data toggles are set to DATA0. Now the device functions may be used
    } DeviceState;

    DeviceState deviceState, nextDeviceState;

    logic [USB_DEV_ADDR_WID-1:0] nextDeviceAddr;
    logic [USB_DEV_CONF_WID-1:0] nextDeviceConf;

    initial begin
        deviceState = DEVICE_NOT_RESET;
        requestedBytesLeft = 16'b0;
    end

    logic gotAddrAssigned, gotDevConfig;

    // always ack usb resets if we are in the reset state
    assign ackUsbResetDetect_o = deviceState == DEVICE_RESET;

    always_comb begin
        nextDeviceState = deviceState;
        nextDeviceAddr = deviceAddr_o;
        nextDeviceConf = deviceConf_o;

        if (usbResetDetected_i) begin
            nextDeviceState = DEVICE_RESET;
            nextDeviceAddr = {USB_DEV_ADDR_WID{1'b0}};
            nextDeviceConf = {USB_DEV_CONF_WID{1'b0}};
        end else begin
            unique case (1'b1)
                gotDevConfig: begin
                    nextDeviceConf = setupDataPacket.wValue[USB_DEV_CONF_WID-1:0];

                    // Update device state dependent on the configuration value!
                    if (nextDeviceConf == 0) begin
                        nextDeviceState = DEVICE_ADDR_ASSIGNED;
                    end else begin
                        nextDeviceState = DEVICE_CONFIGURED;
                    end
                end
                gotAddrAssigned: begin

                    // Update device state dependent on the assigned address!
                    nextDeviceAddr = setupDataPacket.wValue[USB_DEV_ADDR_WID-1:0];
                    if (nextDeviceAddr == 0) begin
                        nextDeviceState = DEVICE_RESET;
                    end else begin
                        nextDeviceState = DEVICE_ADDR_ASSIGNED;
                    end
                end
                default: begin
                    
                end
            endcase
        end
    end

    always_ff @(posedge clk12_i) begin
        deviceState <= nextDeviceState;
        deviceAddr_o <= nextDeviceAddr;
        deviceConf_o <= nextDeviceConf;
    end

    //===============================================================================================================
    // Device Request Handling

    logic epInHandshake;
    assign epInHandshake = EP_IN_dataValid_i && !EP_IN_full_o;
    logic epOutHandshake;
    assign epOutHandshake = EP_OUT_popData_i && EP_OUT_dataAvailable_o;

    localparam EP0_ROM_SIZE = usb_ep_pkg::requiredROMSize(USB_DEV_EP_CONF);
    localparam ROM_IDX_WID = $clog2(EP0_ROM_SIZE);

    logic [7:0] romData;
    logic [ROM_IDX_WID-1:0] romTransReadIdx;

    ep0_rom #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF)
    ) ep0rom (
        .clk(clk12_i),
        .readAddr_i(romTransReadIdx),
        .romData_o(romData)
    );

    logic packetBufRst;
    logic packetBufFull;

    // Maximum packet size for EP0: only 8, 16, 32 or 64 bytes are valid!
    // MUST be 64 for high speed (EP0 only)!
    //localparam BUF_BYTE_COUNT = USB_DEV_EP_CONF.deviceDesc.bMaxPacketSize0;
    // BUT: with out simple implementation we only need to be able to store Setup Packets!
    localparam BUF_BYTE_COUNT = usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT;
    localparam BUF_WID = BUF_BYTE_COUNT * 8;
    logic [BUF_WID-1:0] packetBuf;

    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(BUF_BYTE_COUNT)
    ) packetBufWrapper (
        .clk_i(clk12_i),
        .rst_i(packetBufRst),

        .data_i(EP_IN_data_i),
        .dataValid_i(EP_IN_dataValid_i && byteIsData_i),

        .buffer_o(packetBuf),
        .isFull_o(packetBufFull)
    );

    assign setupDataPacket = usb_dev_req_pkg::SetupDataPacket'(packetBuf[usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT * 8 - 1 : 0]);

    logic isSetupTransStart;
    assign isSetupTransStart = transStartTokenID_i == usb_packet_pkg::PID_SETUP_TOKEN[3:2];

    logic isInTransStart;
    assign isInTransStart = transStartTokenID_i == usb_packet_pkg::PID_IN_TOKEN[3:2];

    typedef enum logic[2:0] {
        IDLE,
        SETUP_STAGE,
        SETUP_STAGE_RESOLVE_ROM_ADDR_ROM_DELAY,
        SETUP_STAGE_RESOLVE_ROM_ADDR,
        DATA_STAGE,
        STATUS_STAGE
    } ControlTransferState;

    ControlTransferState ctrlTransState, nextCtrlTransState;
    logic prevDataDir, patchPrevDataDir;
    logic dataDirChanged;
    assign dataDirChanged = prevDataDir ^ isInTransStart;

    always_ff @(posedge clk12_i) begin
        prevDataDir <= patchPrevDataDir ? setupDataPacket.bmRequestType.dataTransDevToHost : (gotTransStartPacket_i ? isInTransStart : prevDataDir);
    end

    logic hasNoDataStage;
    assign hasNoDataStage = setupDataPacket.wLength == 0;

    assign packetBufRst = ctrlTransState == IDLE;

    initial begin
        ctrlTransState = IDLE;
    end

    logic isRomDataOutSrc, nextIsRomDataOutSrc;
    logic requestError, nextRequestError;
    //logic pidData1Expected, nextPidData1Expected;

    logic [ROM_IDX_WID-1:0] romReadIdx;
    logic [ROM_IDX_WID-1:0] nextRomReadIdx, nextRomTransReadIdx;
    logic [15:0] requestedBytesLeft, nextRequestedBytesLeft;
    logic epOutDataToggleState, nextEpOutDataToggleState;

    initial begin
        //pidData1Expected = 1'b0;
        epOutDataToggleState = 1'b0;
    end

    logic isInStatusStage;
    assign isInStatusStage = ctrlTransState == STATUS_STAGE;

    logic awaitROMData, gotNewROMReq;

    initial begin
        awaitROMData = 1'b0;
    end

    // reset upon configuration event: SetConfiguration() or ClearFeature(ENDPOINT_HALT) device request!
    assign resetDataToggle_o = gotDevConfig; // This flag is only intended for SetConfiguration() and is shared amoung all endpoints
    // we also need to reset the DATA toggle state endpoint specific for ClearFeature(ENDPOINT_HALT) requests!

generate
    always_comb begin
        nextCtrlTransState = ctrlTransState;

        gotNewROMReq = 1'b0;
        gotAddrAssigned = 1'b0;
        gotDevConfig = 1'b0;
        patchPrevDataDir = 1'b0;

        nextRequestedBytesLeft = requestedBytesLeft;
        nextRomReadIdx = romReadIdx;
        nextRomTransReadIdx = romTransReadIdx;
        nextRequestError = requestError;
        nextIsRomDataOutSrc = isRomDataOutSrc;

        unique case (ctrlTransState)
            IDLE: begin
                nextRequestError = 1'b0;

                if (gotTransStartPacket_i && isSetupTransStart) begin
                    nextCtrlTransState = SETUP_STAGE;
                end
            end
            SETUP_STAGE: begin
                //TODO how to handle failed transactions: for now lets stay in the state!
                if (EP_IN_fillTransDone_i && EP_IN_fillTransSuccess_i) begin
                    nextCtrlTransState = hasNoDataStage ? STATUS_STAGE : SETUP_STAGE_RESOLVE_ROM_ADDR_ROM_DELAY;
                    // on the state transition from SETUP_STAGE to DATA_STAGE we need to patch prevDataDir such that the DATA_STAGE wont be skipped immediately!
                    patchPrevDataDir = 1'b1;

                    // The transaction was successful, lets toggle our expected data pid bit!
                    //nextPidData1Expected = !pidData1Expected;

                    nextRequestedBytesLeft = setupDataPacket.wLength;
                    nextIsRomDataOutSrc = 1'b0;

                    // Only handle successful transfers
                    unique case (setupDataPacket.bRequest)
                        usb_dev_req_pkg::SET_ADDRESS: begin
                            /*
                            The spec says:
                            "
                                Stages after the initial Setup packet assume the same device address as the Setup packet.
                                The USB device does not change its device address until after the Status stage of this request is completed successfully.
                                Note that this is a difference between this request and all other requests.
                                For all other requests, the operation indicated must be completed before the Status stage.
                            "
                            The status stage is a different transaction -> we need to delay the address change!
                            */
                            nextRequestError = !`SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        usb_dev_req_pkg::GET_DESCRIPTOR: begin
                            // Our descriptors are read from the ROM
                            nextIsRomDataOutSrc = 1'b1;

                            // By default: error out!
                            nextRequestError = 1'b1;

                            if (`GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState)) begin

                                unique case (setupDataPacket.wValue[15:8])
                                    usb_desc_pkg::DESC_DEVICE: begin
                                        // We only have a single device descriptor!
                                        // Even though we know that the start address is at LUT_ROM_SIZE
                                        // we have an additional LUT entry for a more homogenous execution flow
                                        nextRomReadIdx = {ROM_IDX_WID{1'b0}};
                                        nextRequestError = 1'b0;
                                    end
                                    usb_desc_pkg::DESC_CONFIGURATION: begin
                                        // Depends on the descriptor index!
                                        if (setupDataPacket.wValue[7:0] < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations) begin
                                            // Index is valid
                                            nextRequestError = 1'b0;
                                            nextRomReadIdx = setupDataPacket.wValue[7:0] + 8'b1;
                                        end
                                    end
                                    usb_desc_pkg::DESC_STRING: begin
                                        // Depends on the descriptor index!
                                        if (USB_DEV_EP_CONF.stringDescCount > 0) begin
                                            if (setupDataPacket.wValue[7:0] <= USB_DEV_EP_CONF.stringDescCount[7:0]) begin
                                                // Index is valid
                                                localparam logic[7:0] stringDescReadOffset = USB_DEV_EP_CONF.deviceDesc.bNumConfigurations[7:0] + 8'd1;
                                                nextRequestError = 1'b0;
                                                nextRomReadIdx = stringDescReadOffset + setupDataPacket.wValue[7:0];
                                            end
                                        end
                                    end
                                    default: begin
                                        // By default errors out
                                    end
                                endcase

                            end
                        end
                        usb_dev_req_pkg::GET_CONFIGURATION: begin
                            // Nothing to do here
                            nextRequestError = !`GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        usb_dev_req_pkg::SET_CONFIGURATION: begin
                            if (`SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotDevConfig = 1'b1;
                                nextRequestError = 1'b0;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end

                        //===============================================================================================================================================
                        // NOTE: the following request are not really implemented!
                        // Requests that might not target the device:
                        //     SYNCH_FRAME: endpoint wIndex
                        //     CLEAR_FEATURE: device, interface or endpoint
                        //     SET_FEATURE: device, interface or endpoint
                        //     GET_STATUS: device, interface or endpoint

                        usb_dev_req_pkg::GET_INTERFACE: begin
                            //TODO This request returns the selected alternate setting for the specified interface
                            //TODO as we currently do not allow setting an alternate interface we can simply return 1 byte set to 0 which is the default interface!

                            // Nothing to do here
                            nextRequestError = !`GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        usb_dev_req_pkg::GET_STATUS: begin
                            //TODO This requests returns the status for the specified recipient
                            //TODO as we currently do not support features as remote wakeup or endpoint halting, we can always return 2 bytes set to 0

                            // Nothing to do here
                            nextRequestError = !`GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        usb_dev_req_pkg::SYNCH_FRAME: begin
                            // Is only used for isochronous data transfers using implicit pattern synchronization.
                            //TODO apply
                            //TODO this is required for isochronous endpoints
                            // Nothing to do here
                            nextRequestError = !`SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        /*
                        usb_dev_req_pkg::SET_INTERFACE: begin
                            //TODO select an alternate setting for the specified interface
                            //TODO do we want to support alternate interfaces???
                            nextRequestError = !`SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        */
                        /*
                        usb_dev_req_pkg::SET_DESCRIPTOR: begin
                            // This request is optional to implement
                            nextRequestError = 1'b1;
                        end
                        */
                        /*
                        usb_dev_req_pkg::CLEAR_FEATURE: begin
                            //TODO do we want to support this?
                            nextRequestError = !`CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        usb_dev_req_pkg::SET_FEATURE: begin
                            //TODO do we want to support this?
                            nextRequestError = !`SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState);
                        end
                        */
                        /*
                        usb_dev_req_pkg::RESERVED_2, usb_dev_req_pkg::RESERVED_4: begin
                            nextRequestError = 1'b1;
                        end
                        */
                        default: begin
                            //IMPL_SPECIFIC_13_255
                            // Else we have vendor/implementation specific requests -> delegate?
                            // For now lets just issue an request error
                            nextRequestError = 1'b1;
                        end
                    endcase

                    // reset transaction counter
                    nextRomTransReadIdx = nextRomReadIdx;
                    gotNewROMReq = 1'b1;
                end
            end
            SETUP_STAGE_RESOLVE_ROM_ADDR_ROM_DELAY: begin
                gotNewROMReq = 1'b1;
                nextCtrlTransState = SETUP_STAGE_RESOLVE_ROM_ADDR;
            end
            SETUP_STAGE_RESOLVE_ROM_ADDR: begin
                nextCtrlTransState = DATA_STAGE;
                gotNewROMReq = 1'b1;

                //TODO this does currently only support a single address byte!
                nextRomReadIdx = romData;
                // reset transaction counter
                nextRomTransReadIdx = nextRomReadIdx;
            end
            DATA_STAGE: begin
                if (gotTransStartPacket_i && dataDirChanged) begin
                    nextCtrlTransState = STATUS_STAGE;
                end
            end
            STATUS_STAGE: begin
                //TODO use requestError to signal status as specified in page 227

                //TODO how to handle failed transactions: for now lets stay in the state!
                if ((EP_IN_fillTransDone_i && EP_IN_fillTransSuccess_i) || (EP_OUT_popTransDone_i && EP_OUT_popTransSuccess_i)) begin
                    nextCtrlTransState = IDLE;

                    // Handle SET_ADDRESS edge case: update is only done after the status stage: aka zero length data packet
                    // Check if the previous setup transaction was set address & we had no error before
                    if (!requestError && setupDataPacket.bRequest == usb_dev_req_pkg::SET_ADDRESS) begin
                        // Now we are allowed to update our address!
                        gotAddrAssigned = 1'b1;
                    end
                end
            end
        endcase

        nextEpOutDataToggleState = epOutDataToggleState; //TODO this must probaly be reset for new transactions?
        //nextPidData1Expected = pidData1Expected;

        if (ctrlTransState == DATA_STAGE || isInStatusStage) begin
            if (epOutHandshake) begin
                nextRomTransReadIdx = romTransReadIdx + 1;
                gotNewROMReq = 1'b1;
                nextRequestedBytesLeft = requestedBytesLeft - 1;
            end else if (EP_OUT_popTransDone_i) begin
                if (EP_OUT_popTransSuccess_i) begin
                    // read was successful -> commit transaction counter
                    nextRomReadIdx = romTransReadIdx;
                    // Also toggle the data pid state
                    nextEpOutDataToggleState = !epOutDataToggleState;
                end else begin
                    // read failed -> reset transaction counter
                    nextRomTransReadIdx = romReadIdx;
                end
            end
        end
    end
endgenerate

    always_ff @(posedge clk12_i) begin
        awaitROMData <= gotNewROMReq;
        ctrlTransState <= nextCtrlTransState;

        requestError <= nextRequestError;
        requestedBytesLeft <= nextRequestedBytesLeft;

        epOutDataToggleState <= nextEpOutDataToggleState;
        //TODO this needs to be reset to 0 on transition to certain device states too
        //pidData1Expected <= nextPidData1Expected;

        isRomDataOutSrc <= nextIsRomDataOutSrc;
        romReadIdx <= nextRomReadIdx;
        romTransReadIdx <= nextRomTransReadIdx;
    end

    logic sendDataToHost; //TODO this is not yet correct!
    //assign sendDataToHost = setupDataPacket.bmRequestType.dataTransDevToHost;
    assign sendDataToHost = 1'b1;

    logic expectDataIn; //TODO this is not yet correct!
    // assign expectDataIn = ctrlTransState == SETUP_STAGE || !sendDataToHost;
    assign expectDataIn = 1'b1;

    // Currently we only expect input for a new device request!
    // Overrule this flag if we are in the status stage -> no input is expected!
    assign EP_IN_full_o = !isInStatusStage && (packetBufFull || !expectDataIn);

    // GET_STATUS & GET_INTERFACE are not supported -> return zero bytes
    assign EP_OUT_data_o = isRomDataOutSrc ? romData : (setupDataPacket.bRequest == usb_dev_req_pkg::GET_CONFIGURATION ? deviceConf_o : 8'b0);
    assign EP_OUT_isLastPacketByte_o = requestedBytesLeft == 1;
    // Only show data is available, when we are in a sending state!
    assign EP_OUT_dataAvailable_o = !awaitROMData && requestedBytesLeft != 0 && sendDataToHost;

    // 1'b1 signals that the PID is a handshake (host sent data or we have an request error)
    // Ignore the direction bit if there is no data stage
    assign respHandshakePID_o = (!(hasNoDataStage && isInStatusStage) && !setupDataPacket.bmRequestType.dataTransDevToHost) || requestError;
    // This expects the usb_pe to check this flag only after the end of a corresponding phase
    // Also it is expected that if the device is supposed to send something and respValid_o == 1'b1 and EP_OUT_dataAvailable_o == 1'b0, then a zero length data packet should be send!
    // If a packet was incorrectly received then it is also expected that the usb_pe automatically issues a response timeout and ignores these signals!
    assign respValid_o = !awaitROMData;
    // Ensure DATA1 PID is used for the status stage!
    assign respPacketID_o = requestError ? usb_packet_pkg::RES_STALL : (isInTransStart ? {isInStatusStage || epOutDataToggleState, 1'b0} : usb_packet_pkg::RES_ACK);

endmodule
