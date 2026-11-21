# NanoPi M1 image build project
#
#   make                 build everything that is missing, then the image
#   make kernel          kernel only (delegates to ../nanopi-m1-kernel)
#   make uboot           U-Boot only
#   make rootfs          Debian armhf rootfs only
#   make image           assemble image from existing rootfs
#   make clean           remove out/
#
# Shared cache defaults to ../.cache (same as the kernel project).

PROJECT_DIR := $(CURDIR)

KERNEL_VERSION ?= 6.18.64
UBOOT_VERSION  ?= 2026.07
SUITE          ?= trixie
MIRROR         ?= http://mirrors.aliyun.com/debian
IMG_SIZE       ?= 512M
ROOT_PASSWORD  ?= nanopi
JOBS           ?= $(shell nproc)

NANOPI_M1_CACHE ?= $(abspath $(PROJECT_DIR)/../.cache)
CACHE := $(NANOPI_M1_CACHE)
OUT   := $(PROJECT_DIR)/out

export PROJECT_DIR KERNEL_VERSION UBOOT_VERSION SUITE MIRROR IMG_SIZE \
       ROOT_PASSWORD JOBS CACHE OUT DISTRO

all: kernel uboot rootfs image

# these steps depend on each other, do not parallelise them
.NOTPARALLEL:

kernel:
	@$(MAKE) -C $(PROJECT_DIR)/../nanopi-m1-kernel KERNEL_VERSION=$(KERNEL_VERSION) build

uboot:
	@$(PROJECT_DIR)/scripts/uboot.sh

ROOTFS_KIND ?= busybox
DISTRO ?= $(ROOTFS_KIND)

rootfs: rootfs-$(ROOTFS_KIND)

rootfs-busybox:
	@$(PROJECT_DIR)/scripts/rootfs-busybox.sh

# Debian/Ubuntu need root (mmdebstrap chroots into an armhf tree)
rootfs-debian:
	@sudo -E env "PATH=$$PATH" DISTRO=debian $(PROJECT_DIR)/scripts/rootfs-distro.sh

rootfs-ubuntu:
	@sudo -E env "PATH=$$PATH" DISTRO=ubuntu $(PROJECT_DIR)/scripts/rootfs-distro.sh

# Archived Armbian rootfs + our kernel (no root needed to extract)
rootfs-armbian:
	@$(PROJECT_DIR)/scripts/rootfs-armbian.sh

image:
	@$(PROJECT_DIR)/scripts/image.sh

test:
	@$(PROJECT_DIR)/scripts/qemu-boot-test.py "$$(ls -1 $(OUT)/nanopi-m1-*.img | head -1)"

clean:
	rm -rf $(OUT) $(CACHE)/work-image/rootfs

distclean: clean
	rm -rf $(CACHE)/work-image $(CACHE)/dl/u-boot-$(UBOOT_VERSION).tar.gz

.PHONY: all kernel uboot rootfs image test clean distclean
