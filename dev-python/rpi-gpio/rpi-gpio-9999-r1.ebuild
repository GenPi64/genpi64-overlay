# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI="8"

PYTHON_COMPAT=( python3_{6..11} )

inherit distutils-r1 mercurial

MY_PN="RPi.GPIO"
MY_P="${MY_PN}-${PV}"
DESCRIPTION="RPi.GPIO Python Module"
HOMEPAGE="https://sourceforge.net/projects/raspberry-gpio-python"
EHG_REPO_URI="http://hg.code.sf.net/p/raspberry-gpio-python/code"
#HG_PROJECT="raspberry-gpio-python-code"

LICENSE="MIT"
SLOT="0"
IUSE=""
RESTRICT="nomirror"

DEPEND="
"

RDEPEND="${DEPEND}"

S="${WORKDIR}/${MY_P}"
