{ pkgs, arch, python, version, hash, debianDependencies ? [ ] }:
let
  minor = pkgs.lib.versions.majorMinor version;

  # nixpkgs supplies the build recipe and the toolchain; the interpreter itself
  # is built from the pinned upstream release tarball.
  #
  interpreter = (python.override { mimetypesSupport = false; }).overrideAttrs (_: {
    inherit version;
    src = pkgs.fetchurl {
      url =
        "https://www.python.org/ftp/python/${version}/Python-${version}.tar.xz";
      inherit hash;
    };
  });

  libDir = if arch == "amd64" then "x86_64-linux-gnu" else "aarch64-linux-gnu";
  loader = if arch == "amd64" then
    "/lib64/ld-linux-x86-64.so.2"
  else
    "/lib/ld-linux-aarch64.so.1";
  rpath = "/usr/lib/${libDir}:/usr/lib:/lib/${libDir}:/lib";
in rec {
  inherit version minor;

  # CPython installed under /usr and relinked against the Debian rootfs, so the
  # image carries no Nix runtime closure. allowedReferences = [] enforces that.
  cpython = pkgs.buildPackages.runCommand "cpython-${version}-debian-${arch}" {
    nativeBuildInputs = with pkgs.buildPackages; [
      patchelf
      nukeReferences
      gnused
      gnugrep
      findutils
    ];
    allowedReferences = [ ];
  } ''
    mkdir -p $out/usr/bin $out/usr/lib $out/usr/local/bin

    cp -RL ${interpreter}/lib/python${minor} $out/usr/lib/python${minor}
    cp -L ${interpreter}/lib/libpython${minor}.so.1.0 $out/usr/lib/
    cp -L ${interpreter}/bin/python${minor} $out/usr/bin/
    chmod -R u+w $out

    lib=$out/usr/lib/python${minor}
    rm -rf $lib/test $lib/idlelib $lib/turtledemo $lib/tkinter $lib/config-* \
           $lib/site-packages/sitecustomize.py \
           $lib/site-packages/__pycache__/sitecustomize.*.pyc
    find $out -name '*.a' -delete
    find $out -name '*_test*.so' -delete
    find $out -name 'xxlimited*.so' -delete

    # Point the interpreter at the Debian rootfs instead of the Nix store.
    # Everything nixpkgs baked in below /nix/store maps onto /usr here.
    sed -i "s|'TZPATH': '[^']*'|'TZPATH': '/usr/share/zoneinfo'|" \
      $lib/_sysconfigdata__linux_*.py $lib/site-packages/_sysconfigdata__linux_*.py
    sed -i "s|'/nix/store/[^']*/bin/sh'|'/bin/sh'|" $lib/subprocess.py
    sed -i -E "s|/nix/store/[a-z0-9]{32}-[^/\"' :]*|/usr|g" \
      $lib/_sysconfigdata__linux_*.py $lib/site-packages/_sysconfigdata__linux_*.py
    rm -f $lib/__pycache__/subprocess.*.pyc \
          $lib/__pycache__/_sysconfigdata__linux_*.pyc \
          $lib/site-packages/__pycache__/_sysconfigdata__linux_*.pyc

    grep -q "'TZPATH': '/usr/share/zoneinfo'" $lib/_sysconfigdata__linux_*.py
    grep -q '"/etc/mime.types"' $lib/mimetypes.py
    grep -q "'/bin/sh'" $lib/subprocess.py

    patchelf --set-interpreter ${loader} --set-rpath ${rpath} $out/usr/bin/python${minor}
    for f in $(find $out/usr/lib -name '*.so*' -type f) $out/usr/bin/python${minor}; do
      patchelf --set-rpath ${rpath} "$f"
      patchelf --replace-needed libsqlite3.so libsqlite3.so.0 "$f"
      patchelf --replace-needed libcrypt.so.2 libcrypt.so.1 "$f"
    done

    if patchelf --print-needed $out/usr/bin/python${minor} \
         $(find $out/usr/lib -name '*.so*' -type f) \
       | sort -u | grep -E '^(libcrypt\.so\.2|libsqlite3\.so)$'; then
      echo "unpatched Nix-only soname remains" >&2
      exit 1
    fi

    # Build paths baked into libpython and the precompiled stdlib remain as
    # dead strings; blank them so the image needs no Nix store paths at all.
    find $out -type f -print0 | xargs -0 nuke-refs

    ln -s python${minor} $out/usr/bin/python3
    ln -s python${minor} $out/usr/bin/python
    ln -s /usr/bin/python${minor} $out/usr/local/bin/python${minor}
    ln -s /usr/bin/python${minor} $out/usr/local/bin/python3
    ln -s /usr/bin/python${minor} $out/usr/local/bin/python
  '';

  customPackages = [{
    name = "cpython";
    inherit version;
    type = "application";
    purl = "pkg:github.com/python/cpython@v${version}";
    path = cpython;
    dependencies = debianDependencies;
    properties = [
      {
        name = "cdx:source:url";
        value = "https://www.python.org/ftp/python/${version}/";
      }
      {
        name = "cdx:source:type";
        value = "upstream-source-build";
      }
      {
        name = "cdx:platform";
        value = "linux-${arch}";
      }
      {
        name = "cdx:python:prefix";
        value = "/usr";
      }
    ];
  }];
}
