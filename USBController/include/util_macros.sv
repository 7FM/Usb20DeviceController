`ifndef UTIL_MACROS_SV
`define UTIL_MACROS_SV


`define MUTE_LINT(LINT_NAME) \
        /* verilator lint_off LINT_NAME */ \

`define UNMUTE_LINT(LINT_NAME) \
        /* verilator lint_on LINT_NAME */

`define MUTE_PIN_CONNECT_EMPTY(PIN) \
        `MUTE_LINT(PINCONNECTEMPTY) \
        .PIN() \
        `UNMUTE_LINT(PINCONNECTEMPTY)

`endif
