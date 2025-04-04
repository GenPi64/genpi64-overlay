# Copyright (c) 2017 sakaki <sakaki@deciban.com>
# License: GPL v2 or GPL v3+
# NO WARRANTY

EAPI=8

KEYWORDS="~arm arm64"

DESCRIPTION="udev rule to allow video group RPi argon, rpivid access"
HOMEPAGE="https://github.com/GenPi64/gentoo-on-rpi-64bit"
SRC_URI=""
LICENSE="GPL-3+"
SLOT="0"
IUSE=""
RESTRICT="mirror"

# required by Portage, as we have no SRC_URI...
S="${WORKDIR}"

ACCT_DEPEND="
	acct-group/video
"
DEPEND="
	${ACCT_DEPEND}
	>=virtual/udev-215
	>=app-shells/bash-4.0"
RDEPEND="${DEPEND}"

src_install() {
	insinto "/lib/udev/rules.d"
	doins "${FILESDIR}/99-video-group-access.rules"
}

