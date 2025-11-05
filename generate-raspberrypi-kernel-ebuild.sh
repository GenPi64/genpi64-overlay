#!/usr/bin/env bash
# Script to automatically generate new raspberrypi-kernel ebuild files
# Fetches the latest versions automatically from upstream sources

set -e

echo "Fetching latest Raspberry Pi kernel release..."
LATEST_TAG=$(curl -s https://api.github.com/repos/raspberrypi/linux/tags | grep -o '"name": "stable_[0-9]*"' | head -1 | grep -o '[0-9]*')
if [ -z "$LATEST_TAG" ]; then
    echo "Error: Could not fetch latest Raspberry Pi kernel tag"
    exit 1
fi
STABLE_DATE="$LATEST_TAG"
echo "  Latest stable date: ${STABLE_DATE}"

# Extract kernel version from the tag
echo "Fetching kernel version from tag..."
KERNEL_VERSION=$(curl -sL "https://raw.githubusercontent.com/raspberrypi/linux/stable_${STABLE_DATE}/Makefile" | awk '/^VERSION =/{v=$3} /^PATCHLEVEL =/{p=$3} /^SUBLEVEL =/{s=$3} END{print v"."p"."s}')
if [ -z "$KERNEL_VERSION" ]; then
    echo "Error: Could not determine kernel version"
    exit 1
fi
echo "  Kernel version: ${KERNEL_VERSION}"

# Determine genpatches version (use the major.minor version)
KERNEL_MAJOR_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f1,2)
echo "Checking for genpatches for kernel ${KERNEL_MAJOR_MINOR}..."

# Try to find the latest genpatches version
GENPATCHES_VERSION=""
for i in {50..1}; do
    if curl -sIf "https://dev.gentoo.org/~alicef/dist/genpatches/genpatches-${KERNEL_MAJOR_MINOR}-${i}.base.tar.xz" >/dev/null 2>&1; then
        GENPATCHES_VERSION="${KERNEL_MAJOR_MINOR}-${i}"
        break
    fi
done

if [ -z "$GENPATCHES_VERSION" ]; then
    echo "Warning: Could not find genpatches, using previous version pattern"
    # Fallback to previous minor version
    PREV_MINOR=$(($(echo "$KERNEL_MAJOR_MINOR" | cut -d. -f2) - 1))
    KERNEL_MAJOR=$(echo "$KERNEL_MAJOR_MINOR" | cut -d. -f1)
    GENPATCHES_VERSION="${KERNEL_MAJOR}.${PREV_MINOR}-38"
fi
echo "  Genpatches version: ${GENPATCHES_VERSION}"

# Fetch latest gentoo-kernel-config version
echo "Fetching latest gentoo-kernel-config version..."
GENTOO_CONFIG_VERSION=$(curl -s https://api.github.com/repos/projg2/gentoo-kernel-config/tags | grep -o '"name": "g[0-9]*"' | head -1 | grep -o 'g[0-9]*' || echo "")
if [ -z "$GENTOO_CONFIG_VERSION" ]; then
    GENTOO_CONFIG_VERSION="g17" # A known good fallback
    echo "  Warning: Could not fetch, using fallback: ${GENTOO_CONFIG_VERSION}"
else
    echo "  Gentoo config version: ${GENTOO_CONFIG_VERSION}"
fi

# Fetch latest fedora-kernel-config version for the kernel series
echo "Fetching latest fedora-kernel-config version..."
ALL_TAGS=$(curl -s https://api.github.com/repos/projg2/fedora-kernel-config-for-gentoo/tags | grep -o '"name": "[^"]*"' | cut -d'"' -f4 | grep -- "-gentoo$" | sort -V)

# Try exact kernel series match (e.g., 6.6.x-gentoo)
CONFIG_VERSION=$(echo "$ALL_TAGS" | grep "^${KERNEL_MAJOR_MINOR}\." | tail -1)

# If no exact match, find the latest version that is not newer than the current kernel
if [ -z "$CONFIG_VERSION" ]; then
    echo "  No exact match for ${KERNEL_MAJOR_MINOR}, finding latest version older than ${KERNEL_VERSION}..."
    # Filter tags that are less than or equal to the current kernel version and take the latest one
    CONFIG_VERSION=$(echo "$ALL_TAGS" | awk -v ver="${KERNEL_VERSION}" '{ if ($1 <= ver) print $1 }' | tail -1)
fi

if [ -z "$CONFIG_VERSION" ]; then
    echo "Error: Could not determine a valid fedora-kernel-config version."
    exit 1
else
    echo "  Found potential config version: ${CONFIG_VERSION}"
fi

# Verify the found config version actually exists
FEDORA_CONFIG_URL="https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/${CONFIG_VERSION}/kernel-x86_64-fedora.config"
echo "  Verifying URL: ${FEDORA_CONFIG_URL}"
if ! curl -s --head --fail "${FEDORA_CONFIG_URL}" > /dev/null; then
    echo "Error: Fedora config version ${CONFIG_VERSION} does not exist at expected URL."
    exit 1
fi
echo "  Config version is valid: ${CONFIG_VERSION}"

# Determine revision number
REVISION=1
EBUILD_DIR="sys-kernel/raspberrypi-kernel"
while [ -f "${EBUILD_DIR}/raspberrypi-kernel-${KERNEL_VERSION}-r${REVISION}.ebuild" ]; do
    REVISION=$((REVISION + 1))
done
echo "  Using revision: r${REVISION}"

EBUILD_NAME="raspberrypi-kernel-${KERNEL_VERSION}-r${REVISION}.ebuild"
EBUILD_PATH="${EBUILD_DIR}/${EBUILD_NAME}"

# Get current year for copyright
CURRENT_YEAR=$(date +%Y)

echo ""
echo "Generating ebuild: ${EBUILD_PATH}"
echo ""

# Create the ebuild file
cat > "${EBUILD_PATH}" << EOF
# Copyright 2020-${CURRENT_YEAR} Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# Largely derived from gentoo-kernel-${KERNEL_VERSION}.ebuild

EAPI=8

inherit pikernel-build

MY_P=linux-stable_${STABLE_DATE}
GENPATCHES_P=genpatches-${GENPATCHES_VERSION}
# https://koji.fedoraproject.org/koji/packageinfo?packageID=8
# forked to https://github.com/projg2/fedora-kernel-config-for-gentoo
CONFIG_VER=${CONFIG_VERSION}
GENTOO_CONFIG_VER=${GENTOO_CONFIG_VERSION}

DESCRIPTION="Raspberry Pi Foundation Linux kernel built with Gentoo patches"
HOMEPAGE="
	https://wiki.gentoo.org/wiki/Project:Distribution_Kernel
	https://www.kernel.org/
	https://github.com/raspberrypi/linux
"
SRC_URI+="
	https://github.com/raspberrypi/linux/archive/refs/tags/stable_${STABLE_DATE}.tar.gz -> rpi-$(MY_P).tar.gz
	https://dev.gentoo.org/~alicef/dist/genpatches/\${GENPATCHES_P}.base.tar.xz
	https://dev.gentoo.org/~alicef/dist/genpatches/\${GENPATCHES_P}.extras.tar.xz
	https://github.com/projg2/gentoo-kernel-config/archive/\${GENTOO_CONFIG_VER}.tar.gz
		-> gentoo-kernel-config-\${GENTOO_CONFIG_VER}.tar.gz
	amd64? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/\${CONFIG_VER}/kernel-x86_64-fedora.config
			-> kernel-x86_64-fedora.config.\${CONFIG_VER}
	)
	arm64? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/\${CONFIG_VER}/kernel-aarch64-fedora.config
			-> kernel-aarch64-fedora.config.\${CONFIG_VER}
	)
	ppc64? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/\${CONFIG_VER}/kernel-ppc64le-fedora.config
			-> kernel-ppc64le-fedora.config.\${CONFIG_VER}
	)
	x86? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/\${CONFIG_VER}/kernel-i686-fedora.config
			-> kernel-i686-fedora.config.\${CONFIG_VER}
	)
"
S=\${WORKDIR}/\${MY_P}

LICENSE="GPL-2"
KEYWORDS="~arm ~arm64"
IUSE="debug hardened bcm2711 bcm2712"
REQUIRED_USE="
	arm? ( savedconfig )
	hppa? ( savedconfig )
	riscv? ( savedconfig )
	sparc? ( savedconfig )
"

RDEPEND="
	!sys-kernel/gentoo-kernel-bin:\${SLOT}
"
BDEPEND="
	debug? ( dev-util/pahole )
"
PDEPEND="
	>=virtual/dist-kernel-\${PV}
"

QA_FLAGS_IGNORED="
	usr/src/linux-.*/scripts/gcc-plugins/.*.so
	usr/src/linux-.*/vmlinux
	usr/src/linux-.*/arch/powerpc/kernel/vdso.*/vdso.*.so.dbg
"

src_prepare() {
	# Copied from raspberrypi-sources-6.1.21_p20230405.ebuild
	UNIPATCH_EXCLUDE="
		10*
		15*
		1700
		2000
		29*
		3000
		4567"

	# Copied from kernel-2.eclass

	# So now lets get rid of the patch numbers we want to exclude
	for i in \${UNIPATCH_EXCLUDE}; do
		ebegin "Excluding Patch #\${i}"
		rm -f \${WORKDIR}/\${i}* 2>/dev/null;
		eend \$?
	done

	# Only set PATCHES if there are patches remaining...
	if compgen -G "\${WORKDIR}/*.patch" > /dev/null; then
		local PATCHES=(
			# meh, genpatches have no directory
			"\${WORKDIR}"/*.patch
		)
	else
		echo "No patches selected"
	fi

	default
}

# Override function from kernel-install eclass to skip checking of kernel.release file(s).
pkg_preinst() {
	debug-print-function \${FUNCNAME} "\${@}"
}
EOF

echo "✓ Successfully created: ${EBUILD_PATH}"
echo ""
echo "Summary:"
echo "  Kernel version:        ${KERNEL_VERSION}"
echo "  Stable date:           ${STABLE_DATE}"
echo "  Genpatches version:    ${GENPATCHES_VERSION}"
echo "  Config version:        ${CONFIG_VERSION}"
echo "  Gentoo config version: ${GENTOO_CONFIG_VERSION}"
echo "  Revision:              r${REVISION}"
echo ""
echo "Next steps:"
echo "  1. Verify the ebuild is correct: cat ${EBUILD_PATH}"
echo "  2. Generate the manifest: ebuild ${EBUILD_PATH} manifest"
echo "  3. Test the ebuild: emerge -av =${EBUILD_NAME%.ebuild}"
