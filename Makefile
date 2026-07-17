# SunshineBSD top-level Makefile.
#
# Every workflow in this repository goes through here (DOCS/ENGINEERING.MD
# rule 5). Each test suite runs in its own interpreter process.
#
# Usage:
#   make test              run all Lua test suites
#   make test-schema       run one suite
#   make test-rc2runit     run one sh-based suite (also: test-sunsnap,
#                          test-zshrc)
#   make check             everything
#   make example           compile the example config into ./sunconfig-out
#
# OS build (FreeBSD host only, see tools/*.sh):
#   make fetch             fetch the pinned FreeBSD source into vendor/
#   make world             buildworld with the SunshineBSD overlay
#   make kernel            buildkernel KERNCONF=SUNSHINE
#   make image             build dist/sunshinebsd.qcow2 (needs root)
#   make qemu              boot the image (any host with qemu installed)

LUA ?= lua
SH  ?= sh

# OS build knobs
FREEBSD_REF ?=
QEMU     ?= qemu-system-x86_64
QEMU_MEM ?= 4G
QEMU_CPUS ?= 4
IMAGE    ?= dist/sunshinebsd.qcow2
ISO      ?= dist/sunshinebsd-0.1-CURRENT-amd64.iso

LUA_SUITES = \
	test-util \
	test-fs \
	test-registry \
	test-loader \
	test-schema \
	test-gen_rcconf \
	test-gen_zoneinfo \
	test-gen_runit \
	test-gen_meta \
	test-build \
	test-cli

SH_SUITES = test-rc2runit test-sunsnap test-zshrc

.PHONY: all test check example clean $(LUA_SUITES) $(SH_SUITES) \
	fetch brand world kernel image iso qemu qemu-iso \
	wsl-check wsl-world wsl-kernel wsl-iso

all: test

test: $(LUA_SUITES)
	@echo "== all Lua test suites passed =="

$(LUA_SUITES):
	$(LUA) tests/$(subst test-,test_,$@).lua

$(SH_SUITES):
	$(SH) tests/$(subst test-,test_,$@).sh

check: test $(SH_SUITES)
	@echo "== full check passed =="

example:
	$(LUA) src/sunconfig/sunconfig build -c examples/etc-sunshine -o sunconfig-out

clean:
	-rm -rf tests/tmp sunconfig-out

# ---- OS build (Stage 0) ----------------------------------------------
# world/kernel run on FreeBSD or Linux (WSL); image needs FreeBSD + root.
# On Windows, `make wsl-check` / `make wsl-world` run inside WSL.

WSL_DISTRO ?= FedoraLinux-43

fetch:
	$(SH) tools/fetch-freebsd.sh $(FREEBSD_REF)

brand:
	$(SH) tools/brand-freebsd.sh

world:
	$(SH) tools/build-os.sh world

kernel:
	$(SH) tools/build-os.sh kernel

image:
	$(SH) tools/make-image.sh

# Stage 0 test ISO: remaster the pinned upstream FreeBSD release ISO
# with SunshineBSD identity + tooling. Works on Linux/WSL and FreeBSD.
iso:
	$(SH) tools/make-iso.sh

qemu-iso:
	$(QEMU) -m $(QEMU_MEM) -smp $(QEMU_CPUS) \
		-cdrom $(ISO) -boot d \
		-nic user,model=virtio-net-pci

qemu:
	$(QEMU) -m $(QEMU_MEM) -smp $(QEMU_CPUS) \
		-drive file=$(IMAGE),if=virtio \
		-nic user,model=virtio-net-pci \
		-serial mon:stdio

# ---- WSL passthrough (Windows development hosts) ---------------------

wsl-check:
	wsl -d $(WSL_DISTRO) -- make check

wsl-world:
	wsl -d $(WSL_DISTRO) -- sh tools/build-os.sh world

wsl-kernel:
	wsl -d $(WSL_DISTRO) -- sh tools/build-os.sh kernel

wsl-iso:
	wsl -d $(WSL_DISTRO) -- sh tools/make-iso.sh
