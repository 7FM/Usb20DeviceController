module sim_top (
    input logic CLK,
    output logic vga_h_sync,
    output logic vga_v_sync,
    output logic [3:0] vga_R, 
    output logic [3:0] vga_G,
    output logic [3:0] vga_B,
    input logic [3:0] btns
);

    top uut(
        .CLK(CLK),
        .vga_h_sync(vga_h_sync),
        .vga_v_sync(vga_v_sync),
        .vga_R(vga_R), 
        .vga_G(vga_G),
        .vga_B(vga_B),
        .btns(btns)
    );
endmodule
