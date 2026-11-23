#!/usr/bin/env bash
# Build the image variants with nix, load them into Docker and smoke test them.
#
# Tested per variant: the running interpreter is the version flake.nix pins, on
# the expected architecture, as the nonroot user; the CA bundle is present; the
# minimal image has neither a shell nor npm while the debug image has both; and
# test/test.js passes inside the container.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

usage() {
	cat <<'EOF'
Usage: scripts/test-images.sh [options]

  -v, --versions 24,26   streams to test        (default: every stream in flake.nix)
  -a, --arches   amd64   architectures to test  (default: the host architecture)
      --rmi              remove the loaded images again when done
  -h, --help             show this help

Testing a foreign architecture needs Docker to be set up for emulation.
EOF
}

versions=""
arches=""
remove=false

while [ $# -gt 0 ]; do
	case "$1" in
	-v | --versions)
		versions="${2//,/ }"
		shift 2
		;;
	-a | --arches)
		arches="${2//,/ }"
		shift 2
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

# The streams and their versions come from flake.nix, so the expectations can
# never drift from what is actually pinned and built.
if [ -z "$versions" ]; then
	versions=$(sed -n 's/^ *"\([0-9][0-9]*\)" = {$/\1/p' flake.nix | tr '\n' ' ')
fi

pinned_version() {
	sed -n "/\"$1\" = {/,/};/p" flake.nix |
		sed -n 's/.*version = "\([^"]*\)".*/\1/p' | head -1
}

if [ -z "$arches" ]; then
	case "$(uname -m)" in
	arm64 | aarch64) arches="arm64" ;;
	*) arches="amd64" ;;
	esac
fi

buildSystem=$(nix eval --impure --raw --expr builtins.currentSystem)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat >"$work/probe.js" <<'PROBE'
// Asserts the container matches what the build promised. Exits non-zero on any
// failure, so the shell around it needs no output parsing.
const fs = require('fs');
const { execFileSync } = require('child_process');

const want = {
  version: process.env.EXPECT_VERSION,
  arch: process.env.EXPECT_ARCH,
  shell: process.env.EXPECT_SHELL === 'yes',
  npm: process.env.EXPECT_NPM === 'yes',
};

let failed = 0;
const check = (name, actual, expected) => {
  const ok = actual === expected;
  if (!ok) failed++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${actual}${ok ? '' : ` (expected ${expected})`}`);
};

check('node version', process.version, `v${want.version}`);
check('architecture', process.arch, want.arch);
check('platform', process.platform, 'linux');
check('uid:gid', `${process.getuid()}:${process.getgid()}`, '53111:53111');
check('workdir', process.cwd(), '/home/nonroot');

for (const path of ['/bin/node', '/usr/bin/node',
                    '/etc/ssl/certs/ca-certificates.crt']) {
  check(`exists ${path}`, fs.existsSync(path), true);
}

// A shell is the whole difference between the minimal and the debug variant.
check('has /bin/sh', fs.existsSync('/bin/sh'), want.shell);
check('has /bin/busybox', fs.existsSync('/bin/busybox'), want.shell);

// The package managers ship with the standard image only. lstat, not
// existsSync: a dangling symlink left behind by a partial removal still has to
// count as present.
const present = (p) => { try { fs.lstatSync(p); return true; } catch { return false; } };
for (const path of ['/bin/npm', '/bin/npx', '/usr/bin/npm', '/usr/bin/npx',
                    '/lib/node_modules']) {
  check(`has ${path}`, present(path), want.npm);
}

// corepack only has to be gone from the minimal image. Whether it is there at
// all is the stream's business - Node 24 ships it, Node 26 dropped it.
if (!want.npm) check('has /bin/corepack', present('/bin/corepack'), false);

// npm has to run, and be the version its own package.json claims.
if (want.npm) {
  const npmCli = '/lib/node_modules/npm/bin/npm-cli.js';
  const npmPkg = JSON.parse(fs.readFileSync('/lib/node_modules/npm/package.json', 'utf8'));
  check('npm --version', execFileSync(process.execPath, [npmCli, '--version']).toString().trim(),
    npmPkg.version);
}

// dockerTools.buildLayeredImage delivers the rootfs as a symlink farm into
// the store: the files live in /nix/store/...-image-root and / is links into
// it. That is by design - one copy of the bytes, shared layers between tags -
// so it is reported, not asserted. What does have to hold is that every link
// resolves: a dangling one means content was left out of the image.
const dangling = [];
let storeLinks = 0;
const skip = new Set(['/nix', '/proc', '/sys', '/dev']);
const walk = (dir) => {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    const path = (dir === '/' ? '' : dir) + '/' + entry.name;
    if (skip.has(path)) continue;
    if (entry.isSymbolicLink()) {
      const target = fs.readlinkSync(path);
      if (target.startsWith('/nix/store')) storeLinks++;
      if (!fs.existsSync(path)) dangling.push(`${path} -> ${target}`);
    } else if (entry.isDirectory()) {
      walk(path);
    }
  }
};
walk('/');

check('no dangling symlinks', dangling.length, 0);
for (const link of dangling.slice(0, 5)) console.log(`       ${link}`);
if (dangling.length > 5) console.log(`       ... and ${dangling.length - 5} more`);
console.log(`note  rootfs is store-backed: ${storeLinks} symlinks into /nix/store`);

process.exit(failed === 0 ? 0 : 1);
PROBE

pass=0
fail=0
loaded=""

run_case() { # <name> <command...>
	local name="$1"
	shift
	if "$@" >"$work/out.log" 2>&1; then
		sed 's/^/    /' "$work/out.log"
		echo "  PASS $name"
		pass=$((pass + 1))
	else
		sed 's/^/    /' "$work/out.log"
		echo "  FAIL $name"
		fail=$((fail + 1))
	fi
}

for version in $versions; do
	nodeVersion=$(pinned_version "$version")
	if [ -z "$nodeVersion" ]; then
		echo "no version pinned for stream $version in flake.nix" >&2
		exit 1
	fi

	for arch in $arches; do
		# process.arch reports the Node.js spelling, not the Debian one, the
		# same mapping node-custom.nix makes to build the tarball URL.
		if [ "$arch" = amd64 ]; then nodeArch=x64; else nodeArch="$arch"; fi

		for variant in minimal debug; do
			# The "minimal" build is what CI publishes as the -minimal tag;
			# the debug build is the standard tag, shell and npm included.
			if [ "$variant" = minimal ]; then
				attr="nodejs-${version}-${arch}"
				shell=no
				npm=no
			else
				attr="nodejs-debug-${version}-${arch}"
				shell=yes
				npm=yes
			fi

			echo
			echo "=== $attr (node $nodeVersion) ==="

			tarball=$(nix build --no-update-lock-file --no-link --print-out-paths \
				".#packages.\"${buildSystem}\".\"${attr}\"")

			image=$(docker load -i "$tarball" | sed -n 's/^Loaded image: //p')
			if [ -z "$image" ]; then
				echo "  FAIL could not load $tarball into Docker"
				fail=$((fail + 1))
				continue
			fi
			loaded="$loaded $image"
			echo "  loaded $image"

			run=(docker run --rm --platform "linux/$arch"
				-v "$work:/probe:ro" -v "$repo/test:/test:ro"
				-e "EXPECT_VERSION=$nodeVersion" -e "EXPECT_ARCH=$nodeArch"
				-e "EXPECT_SHELL=$shell" -e "EXPECT_NPM=$npm" "$image")

			run_case "image contract" "${run[@]}" /bin/node /probe/probe.js
			run_case "test/test.js" "${run[@]}" /bin/node /test/test.js

			if [ "$variant" = debug ]; then
				# The debug image is the one CI runs its smoke test in, which
				# needs node reachable through a shell on PATH.
				run_case "busybox shell" "${run[@]}" \
					/bin/sh -c 'busybox true && node /test/test.js'
			fi
		done
	done
done

if [ "$remove" = true ] && [ -n "$loaded" ]; then
	# shellcheck disable=SC2086 # deliberate word splitting into image arguments
	docker rmi $loaded >/dev/null
	echo
	echo "removed the loaded images again"
fi

echo
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
