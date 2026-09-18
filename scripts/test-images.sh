#!/usr/bin/env bash
# Copyright 2025 Zentrum für Digitale Souveränität der Öffentlichen Verwaltung (ZenDiS) GmbH.
# SPDX-License-Identifier: MIT
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

usage() {
	cat <<'EOF'
Usage: scripts/test-images.sh [options]

  -a, --arches amd64,arm64   architectures to test  (default: both)
      --no-docker            skip the container smoke test
      --rmi                  remove the loaded images again when done
  -h, --help                 show this help

Every image is checked by inspecting the built tarball, so both architectures
can be tested on any host. test/test_toplevel_packages.sh additionally runs
inside the debug image when Docker can execute that architecture.
EOF
}

arches="amd64 arm64"
use_docker=true
remove=false

while [ $# -gt 0 ]; do
	case "$1" in
	-a | --arches)
		arches="${2//,/ }"
		shift 2
		;;
	--no-docker)
		use_docker=false
		shift
		;;
	--rmi)
		remove=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "unknown argument: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

buildSystem=$(nix eval --impure --raw --expr builtins.currentSystem)
case "$(uname -m)" in
arm64 | aarch64) hostArch=arm64 ;;
*) hostArch=amd64 ;;
esac
command -v docker >/dev/null 2>&1 || use_docker=false

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
loaded=""

ok() {
	echo "  PASS $*"
	pass=$((pass + 1))
}

bad() {
	echo "  FAIL $*"
	fail=$((fail + 1))
}

list_entries() {
	local dir="$1"
	for layer in "$dir"/*/layer.tar; do
		tar tvf "$layer"
	done | awk '
		{
			i = index($0, " -> ")
			head = (i ? substr($0, 1, i - 1) : $0)
			target = (i ? substr($0, i + 4) : "")
			n = split(head, f, " ")
			path = f[n]
			sub(/^\.\//, "/", path)
			sub(/\/$/, "", path)
			print substr($1, 1, 1) "\t" path "\t" target
		}
	'
}

resolve() {
	local path="$1" entry type target i=0
	while [ "$i" -lt 10 ]; do
		entry=$(awk -F'\t' -v p="$path" '$2 == p { print $1 "\t" $3; exit }' "$entries")
		[ -n "$entry" ] || return 1
		type=${entry%%$'\t'*}
		target=${entry#*$'\t'}
		[ "$type" = l ] || return 0
		case "$target" in
		/*) path="$target" ;;
		*) path="${path%/*}/$target" ;;
		esac
		i=$((i + 1))
	done
	return 1
}

check_present() {
	if resolve "$1"; then ok "$1"; else bad "$1 (missing or dangling)"; fi
}

check_absent() {
	if resolve "$1"; then bad "$1 (present, must not be)"; else ok "no $1"; fi
}

check_config() {
	if grep -qE "\"$1\": *\"$2\"" "$config"; then ok "$1 $2"; else bad "$1 $2"; fi
}

for arch in $arches; do
	case "$arch" in
	amd64)
		triplet=x86_64-linux-gnu
		linker=/lib64/ld-linux-x86-64.so.2
		;;
	arm64)
		triplet=aarch64-linux-gnu
		linker=/lib/ld-linux-aarch64.so.1
		;;
	*)
		echo "unknown architecture: $arch" >&2
		exit 1
		;;
	esac

	for variant in minimal debug; do
		if [ "$variant" = minimal ]; then
			attr="base-0-${arch}"
		else
			attr="base-debug-0-${arch}"
		fi

		echo
		echo "=== $attr ==="

		if ! tarball=$(nix build --no-update-lock-file --no-link --print-out-paths \
			".#packages.\"${buildSystem}\".\"${attr}\"" 2>"$work/build.log"); then
			grep -m1 '^error:' "$work/build.log" | sed 's/^/    /'
			drv=$(sed -n "s/^error: Cannot build '\(.*\.drv\)'.*/\1/p" "$work/build.log" | head -1)
			if [ -n "$drv" ]; then
				nix log "$drv" 2>/dev/null | grep -viE '^\s*\+' | tail -15 | sed 's/^/    /'
			fi
			bad "nix build $attr"
			continue
		fi

		dir="$work/$attr"
		mkdir -p "$dir"
		tar xzf "$tarball" -C "$dir"
		entries="$dir/entries"
		list_entries "$dir" >"$entries"

		config=$(find "$dir" -maxdepth 1 -name '*.json' ! -name manifest.json ! -name repositories)
		check_config architecture "$arch"
		check_config os linux
		check_config User 53111:53111
		check_config WorkingDir /home/nonroot

		check_present /etc/ssl/certs/ca-certificates.crt
		check_present /etc/localtime
		check_present /usr/share/zoneinfo/UTC
		check_present /usr/share/zoneinfo/Europe/Berlin
		check_present "/usr/lib/${triplet}/libc.so.6"
		check_present "/usr/lib/${triplet}/libssl.so.3"
		check_present "$linker"

		if [ "$variant" = minimal ]; then
			check_absent /bin/sh
			check_absent /bin/busybox
		else
			check_present /bin/sh
			check_present /bin/busybox
		fi

		if [ "$variant" = debug ] && [ "$use_docker" != true ]; then
			echo "  SKIP test/test_toplevel_packages.sh (docker unavailable or disabled)"
		elif [ "$variant" = debug ] && [ "$arch" != "$hostArch" ]; then
			echo "  SKIP test/test_toplevel_packages.sh ($arch is not the host architecture)"
		elif [ "$variant" = debug ]; then
			image=$(docker load -i "$tarball" | sed -n 's/^Loaded image: //p')
			if [ -z "$image" ]; then
				bad "docker load"
				continue
			fi
			loaded="$loaded $image"
			if docker run --rm --platform "linux/$arch" -v "$repo/test:/test:ro" \
				"$image" /bin/sh /test/test_toplevel_packages.sh >"$work/out.log" 2>&1; then
				sed 's/^/    /' "$work/out.log"
				ok "test/test_toplevel_packages.sh"
			else
				sed 's/^/    /' "$work/out.log"
				bad "test/test_toplevel_packages.sh"
			fi
		fi
	done
done

if [ "$remove" = true ] && [ -n "$loaded" ]; then
	# shellcheck disable=SC2086
	docker rmi $loaded >/dev/null
	echo
	echo "removed the loaded images again"
fi

echo
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
