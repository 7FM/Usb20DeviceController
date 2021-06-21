`include "usb_ep_pkg.sv"
`include "usb_desc_pkg.sv"
`include "usb_dev_req_pkg.sv"
`include "usb_packet_pkg.sv"

// AKA control endpoint with address 0
module usb_endpoint_0 #(
    parameter USB_DEV_ADDR_WID = 7,
    parameter USB_DEV_CONF_WID = 8,
    parameter usb_ep_pkg::ControlEndpointConfig EP_CONF
)(
    input logic clk48,

    input logic usbResetDetected,
    output logic ackUsbResetDetect,
    output logic [USB_DEV_ADDR_WID-1:0] deviceAddr,
    output logic [USB_DEV_CONF_WID-1:0] deviceConf,

    input logic gotTransStartPacket,
    input usb_packet_pkg::PID_Types transStartPID,

    // Device IN interface
    input logic EP_IN_fillTransDone,
    input logic EP_IN_fillTransSuccess,
    input logic EP_IN_dataValid,
    input logic [7:0] EP_IN_dataIn,
    output logic EP_IN_full,

    /*
    input logic EP_IN_popTransDone,
    input logic EP_IN_popTransSuccess,
    input logic EP_IN_popData,
    output logic EP_IN_dataAvailable,
    output logic [7:0] EP_IN_dataOut,
    */

    // Device OUT interface
    /*
    input logic EP_OUT_fillTransDone,
    input logic EP_OUT_fillTransSuccess,
    input logic EP_OUT_dataValid,
    input logic [7:0] EP_OUT_dataIn,
    output logic EP_OUT_full,
    */

    input logic EP_OUT_popTransDone,
    input logic EP_OUT_popTransSuccess,
    input logic EP_OUT_popData,
    output logic EP_OUT_dataAvailable,
    output logic EP_OUT_isLastPacketByte, //TODO
    output logic [7:0] EP_OUT_dataOut
);

    usb_dev_req_pkg::SetupDataPacket setupDataPacket;

    //===============================================================================================================
    // Device State

    //logic suspended; // Currently not supported / considered
    typedef enum logic[1:0] {
        DEVICE_NOT_RESET = 0, // Ignore all transactions except reset signal
        DEVICE_RESET, // Responds to device and configuration descriptor requests & return information, uses default address
        DEVICE_ADDR_ASSIGNED, // responds to requests to default control pipe with default address as long as no address was assigned
        DEVICE_CONFIGURED // processed a SetConfiguration() request with non zero configuration value & endpoints data toggles are set to DATA0. Now the device functions may be used
    } DeviceState;

    DeviceState deviceState, nextDeviceState;

    logic [USB_DEV_ADDR_WID-1:0] nextDeviceAddr;
    logic [USB_DEV_CONF_WID-1:0] nextDeviceConf;

    initial begin
        deviceState = DEVICE_NOT_RESET;
        //TODO does deviceAddr/deviceConf require an explicit initial Reset? or is relying on usb DEVICE RESET enough?
    end

    logic gotAddrAssigned, gotDevConfig;

    always_comb begin
        nextDeviceState = deviceState;
        nextDeviceAddr = deviceAddr;
        nextDeviceConf = deviceConf;

        // always ack usb resets if we are in the reset state 
        ackUsbResetDetect = deviceState == DEVICE_RESET;

        if (usbResetDetected) begin
            nextDeviceState = DEVICE_RESET;
            nextDeviceAddr = {USB_DEV_ADDR_WID{1'b0}};
            nextDeviceConf = {USB_DEV_CONF_WID{1'b0}};
        end else begin
            if (gotDevConfig) begin
                nextDeviceConf = setupDataPacket.wValue[USB_DEV_CONF_WID-1:0];

                // Update device state dependent on the configuration value!
                if (nextDeviceConf == 0) begin
                    nextDeviceState = DEVICE_ADDR_ASSIGNED;
                end else begin
                    nextDeviceState = DEVICE_CONFIGURED;
                end
            end else if (gotAddrAssigned) begin

                // Update device state dependent on the assigned address!
                nextDeviceAddr = setupDataPacket.wValue[USB_DEV_ADDR_WID-1:0];
                if (nextDeviceAddr == 0) begin
                    nextDeviceState = DEVICE_RESET;
                end else begin
                    nextDeviceState = DEVICE_ADDR_ASSIGNED;
                end
            end
        end
    end

    always_ff @(posedge clk48) begin
        deviceState <= nextDeviceState;
        deviceAddr <= nextDeviceAddr;
    end

    //TODO adjust data width
    typedef enum logic[1:0] {
        //TODO
        NEW_DEV_REQUEST,
        HANDLE_REQUEST
    } EP0_State;

    localparam BUF_BYTE_COUNT = 64;
    logic packetBufRst;
    logic packetBufFull;
    
    localparam BUF_WID = BUF_BYTE_COUNT * 8;

    logic [BUF_WID-1:0] packetBuf;

    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(BUF_BYTE_COUNT)
    ) packetBufWrapper (
        .clk(clk48),
        .rst(packetBufRst),

        .dataIn(EP_IN_dataIn),
        .dataValid(EP_IN_dataValid),

        .buffer(packetBuf),
        .isFull(packetBufFull)
    );

    EP0_State ep0State, nextEp0State;
    usb_dev_req_pkg::RequestCode deviceRequest;

    assign setupDataPacket = usb_dev_req_pkg::SetupDataPacket'(packetBuf[usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT * 8 - 1 : 0]);

    initial begin
        ep0State = NEW_DEV_REQUEST;
    end

    assign EP_IN_full = packetBufFull || (ep0State == NEW_DEV_REQUEST ? 1'b0 //TODO
        : setupDataPacket.bmRequestType.dataTransDevToHost /*Error if we expect to send data!*/);

    always_comb begin
        nextEp0State = ep0State;
        gotAddrAssigned = 1'b0;
        gotDevConfig = 1'b0;
        packetBufRst = EP_IN_fillTransDone || gotTransStartPacket;

        // A new transaction started
        if (gotTransStartPacket) begin
            if (transStartPID[3:2] == usb_packet_pkg::PID_SETUP_TOKEN[3:2]) begin
                // it is an setup token -> go to new_dev_req state
                nextEp0State = NEW_DEV_REQUEST;
            end else begin
                //TODO check if PID is valid (i.e. correct DATA toggle value)!
            end
        end else if (ep0State == NEW_DEV_REQUEST) begin
            if (EP_IN_fillTransDone) begin
                nextEp0State = HANDLE_REQUEST;

                if (EP_IN_fillTransSuccess) begin
                    // Only handle successful transfers
                    unique case (setupDataPacket.bRequest)                    
                        usb_dev_req_pkg::GET_STATUS: begin
                            if (`GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::CLEAR_FEATURE: begin
                            if (`CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_FEATURE: begin
                            if (`SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_ADDRESS: begin
                            if (`SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotAddrAssigned = 1'b1;
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::GET_DESCRIPTOR: begin
                            if (`GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_DESCRIPTOR: begin
                            // This request is optional to implement
                            //TODO request error!
                        end
                        usb_dev_req_pkg::GET_CONFIGURATION: begin
                            if (`GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_CONFIGURATION: begin
                            if (`SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotDevConfig = 1'b1;
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::GET_INTERFACE: begin
                            if (`GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_INTERFACE: begin
                            if (`SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SYNCH_FRAME: begin
                            if (`SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                // Is only used for isochronous data transfers using implicit pattern synchronization.
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::RESERVED_2, usb_dev_req_pkg::RESERVED_4: begin
                            //TODO request error!
                        end
                        default: begin
                            //IMPL_SPECIFIC_13_255
                            // Else we have vendor/implementation specific requests -> delegate?
                            // For now lets just issue an request error
                            //TODO request error!
                        end
                    endcase
                end
            end
        end
    end

    always_ff @(posedge clk48) begin
        ep0State <= nextEp0State;
    end

endmodule
