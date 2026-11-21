# NanoPi M1 kernel build project
#
#   make                              build with defaults
#   make KERNEL_VERSION=5.15.225      pick another LTS tree
#   make clean                        remove out/ and extracted sources
#   make distclean                    remove download cache too
#
# Shared cache: by default ../.cache so that nanopi-m1-image reuses the
# toolchain and tarballs. Override with NANOPI_M1_CACHE=/some/dir.

PROJECT_DIR := $(CURDIR)

KERNEL_VERSION ?= 6.18.64
KERNEL_MIRROR  ?= https://cdn.kernel.org/pub/linux/kernel/v6.x
JOBS           ?= $(shell nproc)

NANOPI_M1_CACHE ?= $(abspath $(PROJECT_DIR)/../.cache)
CACHE := $(NANOPI_M1_CACHE)
OUT   := $(PROJECT_DIR)/out

export KERNEL_VERSION KERNEL_MIRROR JOBS CACHE OUT PROJECT_DIR

all: build

build:
	@KERNEL_VERSION=$(KERNEL_VERSION) KERNEL_MIRROR=$(KERNEL_MIRROR) \
	 JOBS=$(JOBS) CACHE=$(CACHE) OUT=$(OUT) \
	 $(PROJECT_DIR)/scripts/build.sh

clean:
	rm -rf $(OUT) $(CACHE)/build/linux-$(KERNEL_VERSION)

distclean:
	rm -rf $(OUT) $(CACHE)/build/linux-$(KERNEL_VERSION) \
	       $(CACHE)/dl/linux-$(KERNEL_VERSION).tar.xz

.PHONY: all build clean distclean
