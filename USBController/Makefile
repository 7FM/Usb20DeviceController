SRC ?= src
SIM_SRC ?= sim_src
OUT ?= bin
BUILDDIR ?= build
V_DIR ?= sim

TOP_MODULE ?= top

LOG ?= build.log

TARGET ?= ice40
TARGET_FREQ ?= 48

ifeq ($(TARGET),ecp5)
    PNR_ARGS ?= --25k --package CABGA256
    CONSTRAINT_ARG ?= --lpf
    CONSTRAINT_SUFFIX ?= lpf
    BITGEN ?= ecppack
    pnr_target := $(BUILDDIR)/$(TOP_MODULE).cfg
	PNR_OUTPUT_ARG := --textcfg
	bit_target := $(OUT)/$(TOP_MODULE).svf
	BIT_OUT_ARG := --svf
	BIT_IN_ARG :=
else ifeq ($(TARGET),ice40)
    PNR_ARGS ?= --up5k --package sg48
    CONSTRAINT_ARG ?= --pcf
    CONSTRAINT_SUFFIX ?= pcf
    BITGEN ?= icepack
    pnr_target := $(BUILDDIR)/$(TOP_MODULE).asc
	PNR_OUTPUT_ARG := --asc
	bit_target := $(OUT)/$(TOP_MODULE).bin
	BIT_OUT_ARG :=
	BIT_IN_ARG :=
else
   $(error Unsupported Target!)
endif

SYN_PREFIX ?=
SYN := $(SYN_PREFIX)yosys
PNR_PREFIX ?=
PNR := $(PNR_PREFIX)nextpnr-$(TARGET)
BITGEN_PREFIX ?=
BITGEN := $(BITGEN_PREFIX)$(BITGEN)
VERILATOR_PREFIX ?=
VERILATOR := $(VERILATOR_PREFIX)verilator

rwildcard=$(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

srcs := $(call rwildcard,$(SRC),*.v)
srcs += $(call rwildcard,$(SRC),*.sv)
constraints := $(call rwildcard,.,*.$(CONSTRAINT_SUFFIX))

sim_srcs := $(call rwildcard,$(SIM_SRC),*.cpp)
deps := $(call rwildcard,$(V_DIR),*.d)

syn_target := $(BUILDDIR)/$(TOP_MODULE).json

CCFLAGS := -g -ffast-math -Wall -O3 -I$(SIM_SRC)
ifeq ($(OS),Windows_NT)
  LDFLAGS := -lmingw32 -lSDL2main -lSDL2
else
  LDFLAGS := -lSDL2
endif

.PHONY: all clean genBitstream sanityChecks

all: genBitstream sanityChecks

sanityChecks: $(LOG)
	@echo "============================================================================================"
	cat $(LOG) | grep -i "info" || true
	@echo "============================================================================================"
	cat $(LOG) | grep -i "issue" || true
	@echo "============================================================================================"
	cat $(LOG) | grep -i "warn" || true
	@echo "============================================================================================"
	cat $(LOG) | grep -i "error" || true
	@echo "============================================================================================"
	cat $(LOG) | grep -i "problem" || true
	@echo "============================================================================================"

# Place and Route
$(pnr_target): $(syn_target) $(constraints)
	@mkdir -p $(BUILDDIR)
	$(PNR) --json $< $(CONSTRAINT_ARG) $(constraints) $(PNR_OUTPUT_ARG) $@ $(PNR_ARGS) --freq $(TARGET_FREQ) >> $(LOG) 2>&1
	@echo "============================================================================================"

genBitstream: $(pnr_target)
	@mkdir -p $(OUT)
	$(BITGEN) $(BIT_IN_ARG) $< $(BIT_OUT_ARG) $(bit_target) >> $(LOG) 2>&1
	@echo "============================================================================================"

# Synthesis
$(syn_target): $(srcs)
	@mkdir -p $(BUILDDIR)
	$(SYN) -p "synth_$(TARGET) -json $@ -top $(TOP_MODULE)" $^ > $(LOG) 2>&1
	@echo "============================================================================================"

$(V_DIR)/Vsim_$(TOP_MODULE): sim_$(TOP_MODULE).cpp $(sim_srcs) $(srcs)
#	$(VERILATOR) -Wall --MMD --MP -DRUN_SIM -DUSE_INTERFACES --Mdir $(V_DIR) --cc -O3 -CFLAGS "$(CCFLAGS)" -LDFLAGS "$(LDFLAGS)" -I$(SRC) --exe sim_$(TOP_MODULE).cpp $(sim_srcs) -sv --top-module sim_$(TOP_MODULE) --trace $(srcs) || true
	$(VERILATOR) -Wall --MMD --MP -DRUN_SIM --Mdir $(V_DIR) --cc -O3 -CFLAGS "$(CCFLAGS)" -LDFLAGS "$(LDFLAGS)" -I$(SRC) --exe sim_$(TOP_MODULE).cpp $(sim_srcs) -sv --top-module sim_$(TOP_MODULE) --trace $(srcs) || true
	@echo "============================================================================================"
	@make -j -C $(V_DIR) -f Vsim_$(TOP_MODULE).mk Vsim_$(TOP_MODULE)
	@echo "============================================================================================"

sim: $(V_DIR)/Vsim_$(TOP_MODULE)

clean:
	rm -rf $(OUT) $(BUILDDIR) $(V_DIR) $(LOG)

-include $(deps)
