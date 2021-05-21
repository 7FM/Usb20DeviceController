`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

// USB Protocol Engine (PE)
module usb_pe #(
    parameter ENDPOINTS = 1
)(
    input logic clk48,

    input logic usbResetDetect,
    output logic ackUsbResetDetect,

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48!
    output logic rxAcceptNewData,
    input logic [7:0] rxData,
    input logic rxIsLastByte,
    input logic rxDataValid,
    input logic keepPacket,

    // Data Transmit Interface: synced with clk48!
    output logic txReqSendPacket,
    output logic txDataValid,
    output logic txIsLastByte,
    output logic [7:0] txData,
    input logic txAcceptNewData
);

/*
Device Transaction State Machine Hierarchy Overview:

    Device_Process_trans
      - Dev_do_OUT: if pid == PID_OUT_TOKEN || pid == PID_OUT_TOKEN
        - Dev_Do_IsochO
        - Dev_Do_BCINTO
        (- Dev_HS_BCO) <- For HighSpeed devices

      - Dev_do_IN: if pid == PID_IN_TOKEN
        - Dev_Do_IsochI
        - Dev_Do_BCINTI

      (- Dev_HS_ping: if pid == PID_SPECIAL_PING) <- For HighSpeed devices

*/

    typedef enum logic[2:0] {
        PE_RST_RX_CLK,
        PE_WAIT_FOR_TRANSACTION,
        PE_DO_OUT_ISO,
        PE_DO_OUT_BCINT,
        PE_DO_IN_ISOCH,
        PE_DO_IN_BCINT
    } PEState;


    typedef enum logic[1:0] {
        BCINTO_RST_RX_CLK,
        BCINTO_AWAIT_PACKET,
        BCINTO_HANDLE_PACKET,
        BCINTO_ISSUE_RESPONSE
    } RX_BCINTState;

    typedef enum logic[1:0] {
        IsochO_RST_RX_CLK,
        IsochO_AWAIT_PACKET,
        IsochO_HANDLE_PACKET
        // Has no handshake phase
    } RX_IsochState;


    typedef enum logic[1:0] {
        BCINTI_ISSUE_PACKET,
        BCINTI_RST_RX_CLK,
        BCINTI_AWAIT_RESPONSE
    } TX_BCINTState;

    typedef enum logic[0:0] {
        IsochI_ISSUE_PACKET
        // Has no handshake phase
    } TX_IsochState;

endmodule