ROOT_DIR := $(realpath ../../..)
include $(ROOT_DIR)/config.mk

# The UCC FU's regression (hw/rtl/ucc). Each device under test is its own Verilator model and executable, all built
# from main.cpp; ucc/verify.py writes the case files and runs them. `make run` runs the model tests and the regression.
#
#   ucc_lane                 the FU
#   ucc_lane_issue_checked   the FU with UCC_CHECK_ISSUE: a breach of the issue rules stops the simulation
#   ucc_fma_bench            ucc_fma with the ports ucc_lane leaves unconnected (bench/)
#   ucc_mul_tiles            the FMA's 53 x 53 product on DPA-16's tiles (bench/)
#   fp64_fma_lane            TransDot's FP64 FMA lane, the FP64 baseline
#   fpnew_fp32_lane          an unchanged fpnew_fma in FP32 with the same pipeline, the FP32 baseline (bench/)

PROJECT := ucc_lane
DEVICES := ucc_lane ucc_lane_issue_checked ucc_fma_bench ucc_mul_tiles fp64_fma_lane fpnew_fp32_lane

SRC_DIR := $(VORTEX_HOME)/hw/unittest/$(PROJECT)
UCC_DIR := $(VORTEX_HOME)/hw/rtl/ucc
TRANSDOT_DIR := $(UCC_DIR)/vendor/transdot
CVFPU_DIR := $(UCC_DIR)/vendor/cvfpu

JOBS ?= $(shell python3 -c 'import multiprocessing as mp; print(mp.cpu_count())')
OUT ?= $(CURDIR)/run
PYTEST := cd $(SRC_DIR) && python3 -m pytest -q -p no:cacheprovider ucc/tests
VERIFY := cd $(SRC_DIR) && python3 -m ucc.verify --bin $(CURDIR) --out $(abspath $(OUT)) --jobs $(JOBS)

ifeq ($(DEVICE),)

all: $(DEVICES)

$(DEVICES):
	$(MAKE) DEVICE=$@

# the model tests (no simulation), then the regression
run: all
	$(PYTEST)
	$(VERIFY)

test:
	$(PYTEST)

verify: all
	$(VERIFY)

clean:
	rm -rf obj_* $(DEVICES) $(abspath $(OUT))

.PHONY: all run test verify clean $(DEVICES)

else

TOP := $(patsubst %_issue_checked,%,$(DEVICE))
PROJECT := $(DEVICE)

# Compilation order: packages, the units the FMAs instantiate, the FU, then the benches
RTL_PKGS += $(addprefix $(TRANSDOT_DIR)/, \
	common_cells/src/cf_math_pkg.sv \
	src/fpnew_pkg.sv \
	common_cells/src/lzc.sv \
	src/fpnew_classifier.sv \
	src/fpnew_rounding.sv \
	src/fpnew_fma.sv \
	nv_tc/simt_units/fp64_fma_lane.sv \
	nv_tc/dpa16/rtl/dpa16_pkg.sv \
	nv_tc/dpa16/rtl/dpa16_unpack.sv \
	nv_tc/dpa16/rtl/dpa16_mul12.sv \
	nv_tc/dpa16/rtl/dpa16_align_sum.sv \
	nv_tc/dpa16/rtl/dpa16_norm.sv)
RTL_PKGS += $(CVFPU_DIR)/src/fpnew_noncomp.sv $(CVFPU_DIR)/src/fpnew_cast_multi.sv
RTL_PKGS += $(SRC_DIR)/bench/fpnew_fp32_lane.sv
RTL_PKGS += $(addprefix $(UCC_DIR)/, \
	ucc_pkg.sv ucc_shift.sv ucc_fp32_ctrl.sv ucc_fp32_norm.sv ucc_fp32_round.sv ucc_tiles.sv ucc_tilemul.sv \
	ucc_int_alu.sv ucc_fp_noncomp.sv ucc_fp_cast.sv ucc_sfu_rom.sv ucc_sfu.sv ucc_dpa16_core.sv ucc_dpa16.sv \
	ucc_fma.sv ucc_lane.sv)
RTL_PKGS += $(SRC_DIR)/bench/ucc_mul_tiles.sv $(SRC_DIR)/bench/ucc_fma_bench.sv
# common.mk reads the top from the include path by its module name
RTL_PKGS := $(filter-out %/$(TOP).sv,$(RTL_PKGS))
# the includes, and the directories of the tops, which common.mk names by module
RTL_INCLUDE := -I$(TRANSDOT_DIR)/common_cells/include -I$(UCC_DIR) -I$(SRC_DIR)/bench -I$(TRANSDOT_DIR)/nv_tc/simt_units

SRCS += $(SRC_DIR)/main.cpp
CXXFLAGS += -DUCC_TOP_$(TOP)
# the vendored files are linted upstream, the FU and its benches here
VL_FLAGS += $(SRC_DIR)/ucc.vlt
VL_FLAGS += --Mdir obj_$(DEVICE)
# straight to Verilator: config.mk can override CONFIGS, and a define dropped here would go unnoticed
ifneq ($(DEVICE),$(TOP))
VL_FLAGS += -DUCC_CHECK_ISSUE
endif

include ../common.mk

# common.mk's dependencies leave out the files named directly and the .svh includes
$(DESTDIR)/$(PROJECT): $(RTL_PKGS) $(SRC_DIR)/ucc.vlt $(wildcard $(TRANSDOT_DIR)/common_cells/include/common_cells/*.svh)

endif
