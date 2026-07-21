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
#   make iso               remaster a bootable ISO (release: sunshine.txz
#                          compressed with xz, smallest download)
#   make iso-dev           same, but sunshine.txz uses zstd -- much faster
#                          to pack, for boot-test iteration (not for release)

LUA ?= lua
SH  ?= sh

# OS build knobs
FREEBSD_REF ?=
QEMU     ?= qemu-system-x86_64
QEMU_MEM ?= 4G
QEMU_CPUS ?= 4
IMAGE    ?= dist/sunshinebsd.qcow2
ISO      ?= dist/sunshinebsd-0.3.1-BETA-amd64.iso
# OVMF UEFI firmware for qemu-iso -- confirmed live 2026-07-18: the
# desktop session (xf86-video-scfb) only gets a usable framebuffer under
# UEFI boot (vt(4)'s GOP path); legacy BIOS boot reproduces "no screens
# found" every time regardless of any Xorg/driver config. Point these at
# a real OVMF build (e.g. QEMU-for-Windows ships one under
# <qemu-install>/share/edk2-x86_64-code.fd; OVMF_VARS must be a writable
# copy, not the read-only template) -- left blank by default since the
# path isn't portable across hosts, so qemu-iso silently falls back to
# legacy BIOS (broken for the desktop session) until both are set.
OVMF_CODE ?=
OVMF_VARS ?=

# Built via ifneq, not $(if ...): GNU Make's $(if cond,then,else) splits on
# every comma, and -drive's own value is comma-separated -- $(if ...) here
# silently mangled the argument (confirmed via `make -n qemu-iso`: it
# dropped "-drive if=pflash," entirely, leaving a bare "format=raw,...").
OVMF_ARGS :=
ifneq ($(OVMF_CODE),)
OVMF_ARGS += -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE)
endif
ifneq ($(OVMF_VARS),)
OVMF_ARGS += -drive if=pflash,format=raw,file=$(OVMF_VARS)
endif

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
	test-cli \
	test-flesk_logo \
	test-flesk_render \
	test-flesk_info \
	test-flesk_cli \
	test-flesk_sysdeps \
	test-pkgfetch_index \
	test-pkgfetch_resolve \
	test-pkgfetch_cli \
	test-pkgfetch_deps \
	test-flash_manifest \
	test-flash_components \
	test-flash_render \
	test-flash_cli \
	test-flash_deps \
	test-flash_start \
	test-flash_enable

SH_SUITES = test-rc2runit test-sunsnap test-zshrc test-provision_accounts test-provision_pkgfiles test-provision_gpu test-provision_procfs test-sddm_launch test-etc_overlay test-iso_parts

.PHONY: all test check example clean $(LUA_SUITES) $(SH_SUITES) \
	fetch brand world kernel image iso iso-dev qemu qemu-iso \
	wsl-check wsl-world wsl-kernel wsl-iso wsl-iso-dev

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

iso-dev:
	SUNSHINE_TXZ_COMPRESSION=zstd $(SH) tools/make-iso.sh

qemu-iso:
	$(QEMU) -m $(QEMU_MEM) -smp $(QEMU_CPUS) -cpu qemu64 -vga std \
		-cdrom $(ISO) -boot d \
		-nic user,model=virtio-net-pci \
		-serial stdio \
		$(OVMF_ARGS)

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

wsl-iso-dev:
	wsl -d $(WSL_DISTRO) -- env SUNSHINE_TXZ_COMPRESSION=zstd sh tools/make-iso.sh
