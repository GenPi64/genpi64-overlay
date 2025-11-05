#!/usr/bin/env python3
# Script to automatically generate new raspberrypi-kernel ebuild files
# Fetches the latest versions automatically from upstream sources

import os
import re
import sys
import datetime
from packaging.version import parse as parse_version

try:
    import requests
except ImportError:
    print("Error: 'requests' library not found. Please install it with 'pip install requests'", file=sys.stderr)
    sys.exit(1)

# --- Configuration ---
HEADERS = {"Accept": "application/vnd.github.v3+json"}
EBUILD_DIR = "sys-kernel/raspberrypi-kernel"

# --- Helper Functions ---

def fetch_json(url):
    """Fetches JSON from a URL and handles errors."""
    try:
        response = requests.get(url, headers=HEADERS)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error fetching URL {url}: {e}", file=sys.stderr)
        return None

def check_url_exists(url):
    """Checks if a URL exists by sending a HEAD request."""
    try:
        response = requests.head(url, timeout=5)
        return response.status_code == 200
    except requests.exceptions.RequestException:
        return False

def get_latest_rpi_kernel_tag():
    """Fetches the latest stable kernel tag from the Raspberry Pi linux repo."""
    print("Fetching latest Raspberry Pi kernel release...")
    tags = fetch_json("https://api.github.com/repos/raspberrypi/linux/tags")
    if not tags:
        return None
    for tag in tags:
        if tag['name'].startswith('stable_'):
            stable_date = tag['name'].replace('stable_', '')
            print(f"  Latest stable date: {stable_date}")
            return stable_date
    return None

def get_kernel_version_from_makefile(stable_date):
    """Extracts the kernel version from the Makefile of a given stable tag."""
    print("Fetching kernel version from tag...")
    url = f"https://raw.githubusercontent.com/raspberrypi/linux/stable_{stable_date}/Makefile"
    try:
        response = requests.get(url)
        response.raise_for_status()
        makefile_content = response.text
        version = re.search(r"^VERSION\s*=\s*(\d+)", makefile_content, re.M)
        patchlevel = re.search(r"^PATCHLEVEL\s*=\s*(\d+)", makefile_content, re.M)
        sublevel = re.search(r"^SUBLEVEL\s*=\s*(\d+)", makefile_content, re.M)
        if version and patchlevel and sublevel:
            kernel_version = f"{version.group(1)}.{patchlevel.group(1)}.{sublevel.group(1)}"
            print(f"  Kernel version: {kernel_version}")
            return kernel_version
    except requests.exceptions.RequestException as e:
        print(f"Error fetching Makefile: {e}", file=sys.stderr)
    return None

def get_genpatches_version(kernel_version):
    """Finds the appropriate genpatches version by checking for existing files."""
    major_minor = ".".join(kernel_version.split('.')[:2])
    print(f"Checking for genpatches for kernel {major_minor}...")
    for i in range(50, 0, -1):
        version_to_check = f"{major_minor}-{i}"
        url = f"https://dev.gentoo.org/~alicef/dist/genpatches/genpatches-{version_to_check}.base.tar.xz"
        if check_url_exists(url):
            print(f"  Genpatches version: {version_to_check}")
            return version_to_check

    print("Warning: Could not find genpatches, using previous version pattern")
    major, minor = major_minor.split('.')
    prev_minor = int(minor) - 1
    fallback_version = f"{major}.{prev_minor}-38"
    print(f"  Genpatches version: {fallback_version}")
    return fallback_version

def get_gentoo_config_version():
    """Fetches the latest gentoo-kernel-config tag."""
    print("Fetching latest gentoo-kernel-config version...")
    tags = fetch_json("https://api.github.com/repos/projg2/gentoo-kernel-config/tags")
    if tags:
        for tag in tags:
            if tag['name'].startswith('g'):
                version = tag['name']
                print(f"  Gentoo config version: {version}")
                return version
    print("  Warning: Could not fetch, using fallback: g17")
    return "g17" # A known good fallback

def get_fedora_config_version(kernel_version):
    """Finds the best matching fedora-kernel-config version."""
    print("Fetching all fedora-kernel-config tags...")
    all_tags = []
    page = 1
    per_page = 100  # Max allowed by GitHub API

    while True:
        url = f"https://api.github.com/repos/projg2/fedora-kernel-config-for-gentoo/tags?page={page}&per_page={per_page}"
        tags = fetch_json(url)
        if not tags:
            break

        all_tags.extend(tags)
        print(f"  Fetched page {page} with {len(tags)} tags (total: {len(all_tags)})")

        # Stop if we got less than the requested number (last page)
        if len(tags) < per_page:
            break

        page += 1

    if not all_tags:
        print("  Error: No tags found in repository", file=sys.stderr)
        return None

    # Filter and sort tags
    gentoo_tags = sorted(
        [tag['name'] for tag in all_tags if tag['name'].endswith('-gentoo')],
        key=lambda v: parse_version(v.replace('-gentoo', '')),
        reverse=True  # Sort in descending order
    )

    print(f"  Found {len(gentoo_tags)} gentoo config tags")
    print(f"  Latest 5 tags: {gentoo_tags[:5]}")

    target_version = parse_version(kernel_version)
    major_minor = f"{target_version.major}.{target_version.minor}"

    # First try exact match
    exact_match = f"{kernel_version}-gentoo"
    if exact_match in gentoo_tags:
        print(f"  Found exact config version: {exact_match}")
        return exact_match

    # Then try minor version matches (6.12.x)
    minor_matches = [tag for tag in gentoo_tags
                     if tag.startswith(f"{major_minor}.") or tag == f"{major_minor}-gentoo"]

    if minor_matches:
        # Get the highest patch version available
        best_minor_match = sorted(
            minor_matches,
            key=lambda v: parse_version(v.replace('-gentoo', ''))
        )[-1]
        print(f"  Found minor version match: {best_minor_match}")

        # Verify the config exists
        config_url = f"https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/{best_minor_match}/kernel-x86_64-fedora.config"
        if check_url_exists(config_url):
            return best_minor_match
        else:
            print(f"  Warning: Config URL doesn't exist for {best_minor_match}", file=sys.stderr)

    # Then try previous minor version (6.11.x)
    prev_minor = int(major_minor.split('.')[1]) - 1
    if prev_minor >= 0:  # Make sure we don't go negative
        prev_major_minor = f"{target_version.major}.{prev_minor}"
        prev_minor_matches = [tag for tag in gentoo_tags
                              if tag.startswith(f"{prev_major_minor}.") or tag == f"{prev_major_minor}-gentoo"]

        if prev_minor_matches:
            best_prev_minor_match = sorted(
                prev_minor_matches,
                key=lambda v: parse_version(v.replace('-gentoo', ''))
            )[-1]
            print(f"  Found previous minor version match: {best_prev_minor_match}")

            # Verify the config exists
            config_url = f"https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/{best_prev_minor_match}/kernel-x86_64-fedora.config"
            if check_url_exists(config_url):
                return best_prev_minor_match
            else:
                print(f"  Warning: Config URL doesn't exist for {best_prev_minor_match}", file=sys.stderr)

    # If we get here, no suitable version was found
    print(f"  Error: Could not find a suitable fedora-kernel-config version for {kernel_version}", file=sys.stderr)
    print(f"  Available gentoo tags: {gentoo_tags}", file=sys.stderr)
    return None



def get_ebuild_revision(kernel_version):
    """Determines the next revision number for the ebuild."""
    revision = 1
    while os.path.exists(os.path.join(EBUILD_DIR, f"raspberrypi-kernel-{kernel_version}-r{revision}.ebuild")):
        revision += 1
    print(f"  Using revision: r{revision}")
    return revision

def generate_ebuild_content(data):
    """Generates the ebuild file content from a template."""
    return f"""# Copyright 2020-{data['current_year']} Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# Largely derived from gentoo-kernel-{data['kernel_version']}.ebuild

EAPI=8

inherit pikernel-build

MY_P=linux-stable_{data['stable_date']}
GENPATCHES_P=genpatches-{data['genpatches_version']}
# https://koji.fedoraproject.org/koji/packageinfo?packageID=8
# forked to https://github.com/projg2/fedora-kernel-config-for-gentoo
CONFIG_VER={data['config_version']}
GENTOO_CONFIG_VER={data['gentoo_config_version']}

DESCRIPTION="Raspberry Pi Foundation Linux kernel built with Gentoo patches"
HOMEPAGE="
	https://wiki.gentoo.org/wiki/Project:Distribution_Kernel
	https://www.kernel.org/
	https://github.com/raspberrypi/linux
"
SRC_URI+="
	https://github.com/raspberrypi/linux/archive/refs/tags/stable_{data['stable_date']}.tar.gz -> rpi-kernel-$(MY_P).tar.gz
	https://dev.gentoo.org/~alicef/dist/genpatches/${{GENPATCHES_P}}.base.tar.xz
	https://dev.gentoo.org/~alicef/dist/genpatches/${{GENPATCHES_P}}.extras.tar.xz
	https://github.com/projg2/gentoo-kernel-config/archive/${{GENTOO_CONFIG_VER}}.tar.gz
		-> gentoo-kernel-config-${{GENTOO_CONFIG_VER}}.tar.gz
	amd64? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/${{CONFIG_VER}}/kernel-x86_64-fedora.config
			-> kernel-x86_64-fedora.config.${{CONFIG_VER}}
	)
	arm64? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/${{CONFIG_VER}}/kernel-aarch64-fedora.config
			-> kernel-aarch64-fedora.config.${{CONFIG_VER}}
	)
	ppc64? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/${{CONFIG_VER}}/kernel-ppc64le-fedora.config
			-> kernel-ppc64le-fedora.config.${{CONFIG_VER}}
	)
	x86? (
		https://raw.githubusercontent.com/projg2/fedora-kernel-config-for-gentoo/${{CONFIG_VER}}/kernel-i686-fedora.config
			-> kernel-i686-fedora.config.${{CONFIG_VER}}
	)
"
S=${{WORKDIR}}/${{MY_P}}

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
	!sys-kernel/gentoo-kernel-bin:${{SLOT}}
"
BDEPEND="
	debug? ( dev-util/pahole )
"
PDEPEND="
	>=virtual/dist-kernel-${{PV}}
"

QA_FLAGS_IGNORED="
	usr/src/linux-.*/scripts/gcc-plugins/.*.so
	usr/src/linux-.*/vmlinux
	usr/src/linux-.*/arch/powerpc/kernel/vdso.*/vdso.*.so.dbg
"

src_prepare() {{
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
	for i in ${{UNIPATCH_EXCLUDE}}; do
		ebegin "Excluding Patch #${{i}}"
		rm -f ${{WORKDIR}}/${{i}}* 2>/dev/null;
		eend $?
	done

	# Only set PATCHES if there are patches remaining...
	if compgen -G "${{WORKDIR}}/*.patch" > /dev/null; then
		local PATCHES=(
			# meh, genpatches have no directory
			"${{WORKDIR}}"/*.patch
		)
	else
		echo "No patches selected"
	fi

	default
}}

# Override function from kernel-install eclass to skip checking of kernel.release file(s).
pkg_preinst() {{
	debug-print-function ${{FUNCNAME}} "${{@}}"
}}
"""

def main():
    """Main script execution."""
    stable_date = get_latest_rpi_kernel_tag()
    if not stable_date:
        sys.exit(1)

    kernel_version = get_kernel_version_from_makefile(stable_date)
    if not kernel_version:
        sys.exit(1)

    genpatches_version = get_genpatches_version(kernel_version)
    if not genpatches_version:
        sys.exit(1)

    gentoo_config_version = get_gentoo_config_version()
    if not gentoo_config_version:
        sys.exit(1)

    config_version = get_fedora_config_version(kernel_version)
    if not config_version:
        sys.exit(1)

    revision = get_ebuild_revision(kernel_version)

    ebuild_name = f"raspberrypi-kernel-{kernel_version}-r{revision}.ebuild"
    ebuild_path = os.path.join(EBUILD_DIR, ebuild_name)

    ebuild_data = {
        'current_year': datetime.date.today().year,
        'kernel_version': kernel_version,
        'stable_date': stable_date,
        'genpatches_version': genpatches_version,
        'config_version': config_version,
        'gentoo_config_version': gentoo_config_version,
    }

    content = generate_ebuild_content(ebuild_data)

    print(f"\nGenerating ebuild: {ebuild_path}\n")

    try:
        os.makedirs(EBUILD_DIR, exist_ok=True)
        with open(ebuild_path, 'w') as f:
            f.write(content)
    except IOError as e:
        print(f"Error writing ebuild file {ebuild_path}: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"✓ Successfully created: {ebuild_path}\n")
    print("Summary:")
    print(f"  Kernel version:        {kernel_version}")
    print(f"  Stable date:           {stable_date}")
    print(f"  Genpatches version:    {genpatches_version}")
    print(f"  Config version:        {config_version}")
    print(f"  Gentoo config version: {gentoo_config_version}")
    print(f"  Revision:              r{revision}\n")
    print("Next steps:")
    print(f"  1. Verify the ebuild is correct: cat {ebuild_path}")
    print(f"  2. Generate the manifest: ebuild {ebuild_path} manifest")
    print(f"  3. Test the ebuild: emerge -av ={ebuild_name.replace('.ebuild', '')}")


if __name__ == "__main__":
    main()

