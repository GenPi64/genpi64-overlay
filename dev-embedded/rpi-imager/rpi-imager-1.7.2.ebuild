
# Copyright 2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit cmake flag-o-matic

MY_PV="1.7.2"

CMAKE_MAKEFILE_GENERATOR="emake"
CMAKE_IN_SOURCE_BUILD=1

DESCRIPTION="Raspberry Pi Imager (WIP ebuild)"
HOMEPAGE="https://github.com/raspberrypi/rpi-imager"
SRC_URI="https://github.com/raspberrypi/rpi-imager/archive/v${MY_PV}.tar.gz"

S="${WORKDIR}/rpi-imager-${MY_PV}"

LICENSE="Apache"
SLOT="0"
KEYWORDS="~arm64 ~amd64"
IUSE=""

DEPEND=""
RDEPEND="${DEPEND}"
BDEPEND="dev-util/cmake"

src_prepare() {
    cmake_src_prepare
}

src_configure() {
    local mycmakeargs=(
    )
    cmake_src_configure
}

