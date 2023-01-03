# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

# inherit --- no eclasses needed

# Description of package.
DESCRIPTION="Small c++ Interface library for the external HX711 chip thru GPIO"

# lg lib homepage
HOMEPAGE="https://github.com/endail/hx711"

# Using of PN variable avoided, Following note in
# https://wiki.gentoo.org/wiki/Basic_guide_to_write_Gentoo_Ebuilds
SRC_URI="https://github.com/endail/hx711/archive/refs/tags/v${PV}.zip -> ${P}.zip"
SRC_URI="https://github.com/endail/hx711/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

# License of the package.
LICENSE="MIT"

# keep single version of the library installed at the same time.
SLOT="0"

# for Raspberry pi
KEYWORDS="arm arm64"

# ebuild doesn't use any USE flags.
# IUSE="arm64"

COMMON_DEPEND=">=dev-libs/lg-0.2"

# Run-time dependencies. none
# RDEPEND=""

# Build-time dependencies that need to be binary compatible with the system
# being built (CHOST). These include libraries that we link against.
# The below is valid if the same run-time depends are required to compile.
DEPEND="${COMMON_DEPEND}"

# Build-time dependencies that are executed during the emerge process, and
# only need to be present in the native build system (CBUILD). Example:
BDEPEND="${COMMON_DEPEND} sys-devel/gcc sys-devel/make app-arch/unzip"

# ########################################################################
# Provided Makefile allows using (mostly) Default phase funtion behaviour:
#   default_pkg_nofetch
#   default_src_unpack
#   default_src_configure
#   default_src_compile
#   default_src_test
#   default_src_install
# #########################################################################

# User's Patch to eliminate illegal use of ldconfig from Makefile following:
# https://forums.gentoo.org/viewtopic-t-796126-start-0.html
# Example: https://github.com/avxsynth/avxsynth/issues/53

src_prepare() {
#   Removes problematic command: ldconfig from Makefile
	sed -i '/ldconfig/d' Makefile || die
	eapply_user
}
