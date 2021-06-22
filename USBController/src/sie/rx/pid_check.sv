module pid_check(
    input logic [3:0] pidP_i,
    input logic [3:0] pidN_i,
    output logic isValid_o
);

    assign isValid_o = &(pidP_i ^ pidN_i);

endmodule
