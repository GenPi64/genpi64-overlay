# Copyright 2019-2023 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

DESCRIPTION="UEFI firmware for Raspberry Pi 4"
HOMEPAGE="https://github.com/pftf/RPi4"
SRC_URI="https://github.com/pftf/${PN}/releases/download/v${PV}/${PN}_UEFI_Firmware_v${PV}.zip"
## use Built Pre-Binaries EFI bins , unzip to /boot/efi  as firmware udates ebuild to  can automate this chore... 

LICENSE="BSD"
SLOT="0"
KEYWORDS="~arm64"
DEPEND="app-arch/unzip"
RDEPEND="!sys-boot/rpi5-uefi"

QA_PREBUILT="*"

src_install() {
    insinto /boot/efi
    doins "${WORKDIR}"/*
}
