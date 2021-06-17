`ifndef SIE_DEFS_PKG_SV
`define SIE_DEFS_PKG_SV

package sie_defs_pkg;

    // SYNC sequence is KJKJ_KJKK
    // NRZI decoded:    0000_0001
    //              ------ time ---->
    // Is send LSB first
    localparam SYNC_VALUE = 8'b1000_0000;

endpackage

`endif
