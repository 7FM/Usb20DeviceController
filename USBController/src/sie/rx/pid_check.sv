module pid_check(
    input logic [3:0] pidP,
    input logic [3:0] pidN,
    output logic isValid
);

    assign isValid = &(pidP ^ pidN);

endmodule
