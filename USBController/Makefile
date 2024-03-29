SRC ?= src
INCLUDE_DIR ?= include
SIM_SRC ?= sim_src
OUT ?= bin
BUILDDIR ?= build
PATCH_DIR ?= patches
V_DIR ?= sim_build

SIM_DUMP_FST ?= 1
SIM_DEFINES ?= -DRUN_SIM
VERILATOR_SIM_OPTIONS ?=

TOP_MODULE ?= top

LOG ?= $(BUILDDIR)/build.log

TARGET ?= ice40
#TARGET_FREQ ?= 48

USE_SV2V ?= 1

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

# Required Tools
SYN_PREFIX ?=
SYN := $(SYN_PREFIX)yosys

PNR_PREFIX ?=
PNR := $(PNR_PREFIX)nextpnr-$(TARGET)

BITGEN_PREFIX ?=
BITGEN := $(BITGEN_PREFIX)$(BITGEN)

VERILATOR_PREFIX ?=
VERILATOR := $(VERILATOR_PREFIX)verilator

SV2V_PREFIX ?=
SV2V := $(SV2V_PREFIX)sv2v

# (System-)Verilog and simulation sources
rwildcard=$(foreach d,$(wildcard $(1:=/*)),$(call rwildcard,$d,$2) $(filter $(subst *,%,$2),$d))

srcs := $(call rwildcard,$(INCLUDE_DIR),*.v)
srcs += $(call rwildcard,$(INCLUDE_DIR),*.sv)
srcs += $(call rwildcard,$(SRC),*.v)
srcs += $(call rwildcard,$(SRC),*.sv)
constraints := $(call rwildcard,.,*.$(CONSTRAINT_SUFFIX))

#sim_srcs := $(call rwildcard,$(SIM_SRC),*.cpp)
sim_targets := $(wildcard $(SIM_SRC)/sim_*.cpp)
sim_tops := $(patsubst sim_%.cpp,%,$(notdir $(sim_targets)))
sim_tops_rules := $(patsubst %.cpp,%,$(notdir $(sim_targets)))
sim_sv2v_tops_rules := $(patsubst sim_%.cpp,sim_sv2v_%,$(notdir $(sim_targets)))

deps := $(call rwildcard,$(V_DIR),*.d)

sv2v_target_imm := $(BUILDDIR)/$(TOP_MODULE).v
sim_sv2v_target_imm := $(V_DIR)/$(TOP_MODULE).v
sv2v_target := $(BUILDDIR)/$(TOP_MODULE).sv
sim_sv2v_target := $(V_DIR)/$(TOP_MODULE).sv
sv2v_syn_patches := $(call rwildcard,$(PATCH_DIR),*.syn_patch)
sv2v_sim_patches := $(call rwildcard,$(PATCH_DIR),*.sim_patch)
sv2v_merged_patch := $(BUILDDIR)/$(TOP_MODULE).patch
sv2v_sim_merged_patch := $(V_DIR)/$(TOP_MODULE).patch

syn_target := $(BUILDDIR)/$(TOP_MODULE).json

PWD := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CCFLAGS := -g -ffast-math -Wall -O3 -I$(PWD)$(SIM_SRC)
LDFLAGS :=

ifeq ($(SIM_DUMP_FST),1)
VERILATOR_SIM_OPTIONS += --trace-fst
CCFLAGS += -DDUMP_FST
endif

# Add simulation defines
VERILATOR_SIM_OPTIONS += $(SIM_DEFINES)
# Randomize initialization values
VERILATOR_SIM_OPTIONS += --x-initial unique --x-assign unique
# Some basic warning flags
VERILATOR_SIM_OPTIONS += -Wall -Werror-IMPLICIT -Werror-PINMISSING -Werror-USERFATAL
# Create dependencies & phonies
VERILATOR_SIM_OPTIONS += --MMD --MP
# make verilator create C++ code 
VERILATOR_SIM_OPTIONS += --cc -O3
# create executable
VERILATOR_SIM_OPTIONS += --exe
# parse systemverilog
VERILATOR_SIM_OPTIONS += --sv
# trace it all
VERILATOR_SIM_OPTIONS += --trace --trace-structs --trace-underscore

.PHONY: all clean genBitstream sanityChecks sim sims sv2v_sims

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
#	$(PNR) --json $< $(CONSTRAINT_ARG) $(constraints) $(PNR_OUTPUT_ARG) $@ $(PNR_ARGS) --freq $(TARGET_FREQ) >> $(LOG) 2>&1; true
	$(PNR) --json $< $(CONSTRAINT_ARG) $(constraints) $(PNR_OUTPUT_ARG) $@ $(PNR_ARGS) >> $(LOG) 2>&1; true
	@echo "============================================================================================"

genBitstream: $(pnr_target)
	@mkdir -p $(OUT)
	$(BITGEN) $(BIT_IN_ARG) $< $(BIT_OUT_ARG) $(bit_target) >> $(LOG) 2>&1
	@echo "============================================================================================"

# Synthesis
ifeq ($(USE_SV2V),1)
$(syn_target): $(sv2v_target)
	@mkdir -p $(BUILDDIR)
	$(SYN) -T -Q -p "synth_$(TARGET) -json $@ -top $(TOP_MODULE)" $^ > $(LOG) 2>&1
else
$(syn_target): $(srcs)
	@mkdir -p $(BUILDDIR)
# Uses patched yosys version to allow specifying include dirs before all files are read
	$(SYN) -T -Q -Z "verilog_defaults -add -I $(INCLUDE_DIR)" -p "synth_$(TARGET) -json $@ -top $(TOP_MODULE)" $^ > $(LOG) 2>&1
endif
	@echo "============================================================================================"

# Merge all patches into a single file
$(sv2v_merged_patch): $(sv2v_syn_patches)
	cat $^ > $@

$(sv2v_sim_merged_patch): $(sv2v_sim_patches)
	cat $^ > $@

# Compile SV files to a single verilog file that yosys can handle, then rename it to an system verilog file
$(sv2v_target): $(sv2v_target_imm) $(sv2v_merged_patch)
	patch -p 1 -d $(BUILDDIR) -i $(PWD)$(sv2v_merged_patch) -o $(PWD)$@
$(sim_sv2v_target): $(sim_sv2v_target_imm) $(sv2v_sim_merged_patch)
	patch -p 1 -d $(V_DIR) -i $(PWD)$(sv2v_sim_merged_patch) -o $(PWD)$@

$(sv2v_target_imm): $(srcs)
	@mkdir -p $(BUILDDIR)
	$(SV2V) -I $(INCLUDE_DIR) --exclude=logic --exclude=always -w $@ $^

$(sim_sv2v_target_imm): $(srcs)
	@mkdir -p $(V_DIR)
	$(SV2V) -I $(INCLUDE_DIR) $(SIM_DEFINES) --exclude=logic --exclude=always -w $@ $^

define GEN_SIM_RULES
.PHONY: sim_$(sim_top)
.PHONY: sim_sv2v_$(sim_top)

sim_sv2v_$(sim_top): $$(V_DIR)/sv2v/$(sim_top)/Vsim_$(sim_top).mk $$(SIM_SRC)/sim_$(sim_top).cpp $(call rwildcard,$(SIM_SRC)/$(sim_top),*.cpp) $(sim_sv2v_target)
	@make -j$$(shell nproc) -C $$(V_DIR)/sv2v/$(sim_top) -f Vsim_$(sim_top).mk Vsim_$(sim_top)
	@echo "============================================================================================"

$$(V_DIR)/sv2v/$(sim_top)/Vsim_$(sim_top).mk: $(call rwildcard,$(SIM_SRC)/$(sim_top),*.cpp) $(sim_sv2v_target)
	@mkdir -p $$(V_DIR)/sv2v/$(sim_top)
	$$(VERILATOR) -j $$(shell nproc) \
		$$(VERILATOR_SIM_OPTIONS) \
		-Wno-PINMISSING -Wno-EOFNEWLINE -Wno-UNUSED \
	 	--Mdir $$(V_DIR)/sv2v/$(sim_top) \
		$$(if $$(PROFILE),--stats --stats-vars --profile-cfuncs,) \
		-CFLAGS "$$(CCFLAGS)$$(if $$(PROFILE), -g -pg,) -I$$(PWD)$$(SIM_SRC)/$(sim_top)" \
	 	-LDFLAGS "$$(LDFLAGS)$$(if $$(PROFILE), -g -pg,)" \
		-I$$(SRC) -I$$(INCLUDE_DIR) \
		$$(PWD)$$(SIM_SRC)/sim_$(sim_top).cpp $(call rwildcard,$$(PWD)$$(SIM_SRC)/$(sim_top),*.cpp) \
		--top-module sim_$(sim_top) $$(sim_sv2v_target) || true
	@echo "============================================================================================"

sim_$(sim_top): $$(V_DIR)/$(sim_top)/Vsim_$(sim_top).mk $$(SIM_SRC)/sim_$(sim_top).cpp $(call rwildcard,$(SIM_SRC)/$(sim_top),*.cpp) $$(srcs)
	@make -j$$(shell nproc) -C $$(V_DIR)/$(sim_top) -f Vsim_$(sim_top).mk Vsim_$(sim_top)
	@echo "============================================================================================"

$$(V_DIR)/$(sim_top)/Vsim_$(sim_top).mk: $(call rwildcard,$(SIM_SRC)/$(sim_top),*.cpp) $$(srcs)
	@mkdir -p $$(V_DIR)/$(sim_top)
	$$(VERILATOR) -j $$(shell nproc) \
		$$(VERILATOR_SIM_OPTIONS) \
	 	--Mdir $$(V_DIR)/$(sim_top) \
		$$(if $$(PROFILE),--stats --stats-vars --profile-cfuncs,) \
		-CFLAGS "$$(CCFLAGS)$$(if $$(PROFILE), -g -pg,) -I$$(PWD)$$(SIM_SRC)/$(sim_top)" \
	 	-LDFLAGS "$$(LDFLAGS)$$(if $$(PROFILE), -g -pg,)" \
		-I$$(SRC) -I$$(INCLUDE_DIR) \
		$$(PWD)$$(SIM_SRC)/sim_$(sim_top).cpp $(call rwildcard,$$(PWD)$$(SIM_SRC)/$(sim_top),*.cpp) \
		--top-module sim_$(sim_top) $$(srcs) || true
	@echo "============================================================================================"
endef

$(foreach sim_top,$(sim_tops), \
	$(eval $(GEN_SIM_RULES)) \
)

# Compile the top module simulation
sim: sim_$(TOP_MODULE)

# Compile all simulations
sims: $(sim_tops_rules)

sv2v_sims: $(sim_sv2v_tops_rules)

clean:
	rm -rf $(OUT) $(BUILDDIR) $(V_DIR) $(LOG)

-include $(deps)
