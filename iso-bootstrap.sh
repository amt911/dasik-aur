#!/usr/bin/env bash
# Get dasik (and your config) onto an Arch live ISO in one command.
#
#   curl -fsSL https://raw.githubusercontent.com/amt911/dasik-aur/main/iso-bootstrap.sh -o bootstrap.sh
#   bash bootstrap.sh
#
# What it does, in order:
#   1. syncs pacman and installs git / github-cli / age
#   2. installs dasik from the .pkg.tar.zst published by the release job
#      (falls back to building the PKGBUILD as an unprivileged user)
#   3. authenticates gh with a device code and clones your private config repo
#
# Flags:
#   --config-repo <owner/name>   private config repo   (default: amt911/dasik-personal-config)
#   --dest <path>                where to clone it     (default: /root/config)
#   --no-clone                   install dasik only
#   --build                      build the PKGBUILD instead of using the release asset
#
# It installs nothing onto a target and touches no disk. The next step after it
# finishes is `dasik plan`, which is also read-only.
set -euo pipefail

PKG_REPO="amt911/dasik-aur"
CONFIG_REPO="amt911/dasik-personal-config"
DEST="/root/config"
CLONE=1
FORCE_BUILD=0

while [ $# -gt 0 ]; do
    case "$1" in
        --config-repo) CONFIG_REPO="$2"; shift 2 ;;
        --dest)        DEST="$2"; shift 2 ;;
        --no-clone)    CLONE=0; shift ;;
        --build)       FORCE_BUILD=1; shift ;;
        -h|--help)     sed -n '2,22p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run this as root (a live ISO already is)"

# The archiso overlay is a fixed-size tmpfs. A build, a package cache and a
# clone all land in it, and running out mid-pacman leaves a half-installed
# system that is confusing to diagnose. Say it up front instead.
avail_mb=$(df -Pm / | awk 'NR==2 {print $4}')
if [ "${avail_mb:-0}" -lt 700 ] && [ -d /run/archiso/cowspace ]; then
    warn "only ${avail_mb}MB free on the ISO overlay. If anything fails with ENOSPC:"
    warn "  mount -o remount,size=75% /run/archiso/cowspace"
fi

say "Syncing pacman"
# A months-old ISO can carry an expired keyring; refreshing it first is the
# documented fix, and it is harmless on a fresh one.
pacman -Sy --noconfirm --needed archlinux-keyring || warn "keyring refresh failed, continuing"
pacman -S --noconfirm --needed git github-cli age

install_from_release() {
    say "Fetching the latest dasik package from $PKG_REPO"
    # NOT the GitHub API: it rate-limits anonymous IPs, and a live ISO is
    # exactly the anonymous IP that has spent its quota. The PKGBUILD on main
    # names the version, raw.githubusercontent.com is not the API, and
    # /releases/latest/download/ is a stable redirect — no JSON anywhere.
    local pkgbuild pkgver pkgrel url
    pkgbuild=$(curl -fsSL "https://raw.githubusercontent.com/$PKG_REPO/main/PKGBUILD") || return 1
    pkgver=$(printf '%s\n' "$pkgbuild" | sed -n 's/^pkgver=//p' | head -n1)
    pkgrel=$(printf '%s\n' "$pkgbuild" | sed -n 's/^pkgrel=//p' | head -n1)
    [ -n "$pkgver" ] && [ -n "$pkgrel" ] || return 1
    url="https://github.com/$PKG_REPO/releases/latest/download/dasik-$pkgver-$pkgrel-any.pkg.tar.zst"
    echo "  $url"
    # --overwrite '*': an ISO months older than the repos hits file conflicts
    # the moment dependencies drag the new world in (e.g. the gcc-libs split —
    # "libgcc: /usr/lib/libgcc_s.so.1 exists in filesystem"). The live session
    # is disposable and this flag never touches the install target, so
    # overwriting HERE is safe; on a current ISO it changes nothing.
    pacman -U --noconfirm --overwrite '*' "$url"
}

install_from_source() {
    say "Building the PKGBUILD"
    # makepkg refuses to run as root; the ISO is root. A throwaway user with
    # pacman rights is the standard way out, and both go away with the ISO.
    # makepkg assumes base-devel (fakeroot, debugedit, …) and the live ISO
    # does not carry it — without this the build dies with "Cannot find the
    # fakeroot binary".
    pacman -S --noconfirm --needed --overwrite '*' base-devel
    id builder > /dev/null 2>&1 || useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/dasik-builder
    trap 'rm -f /etc/sudoers.d/dasik-builder' RETURN

    local build_dir=/tmp/dasik-aur
    rm -rf "$build_dir"
    git clone --depth 1 "https://github.com/$PKG_REPO.git" "$build_dir"
    chown -R builder:builder "$build_dir"
    ( cd "$build_dir" && sudo -u builder makepkg --syncdeps --noconfirm )
    pacman -U --noconfirm --overwrite '*' "$build_dir"/*.pkg.tar.zst
}

if [ "$FORCE_BUILD" = "1" ]; then
    install_from_source
elif ! install_from_release; then
    # The reason is above this line (curl or pacman said it). The classic one
    # is an ISO much older than the repos; a current ISO avoids every variant
    # of that problem.
    warn "release install failed (reason above) — building from source instead"
    install_from_source
fi

say "dasik installed"
dasik --help > /dev/null || die "dasik does not run"
echo "  $(command -v dasik)"

if [ "$CLONE" = "1" ]; then
    say "Cloning $CONFIG_REPO"
    if ! gh auth status > /dev/null 2>&1; then
        # gh's device flow prints an 8-character code to type on your phone —
        # no token to copy onto the ISO, no SSH key on the pendrive. It needs a
        # terminal, which a `curl | bash` pipe does not have.
        if [ -t 0 ]; then
            gh auth login --hostname github.com --git-protocol https --web
        elif [ -e /dev/tty ]; then
            gh auth login --hostname github.com --git-protocol https --web < /dev/tty
        else
            die "gh needs a terminal. Download the script and run it: bash bootstrap.sh"
        fi
    fi
    if [ -e "$DEST" ]; then
        warn "$DEST already exists, leaving it alone"
    else
        gh repo clone "$CONFIG_REPO" "$DEST"
    fi
fi

say "Next steps"
cat <<EOF
  dasik check $DEST/<config>.json     # validates the JSON + schema, touches nothing
  dasik plan  $DEST/<config>.json     # the dry run: every change it would make
  dasik apply $DEST/<config>.json     # DESTRUCTIVE: partitions, formats, pacstraps

  Sample configs shipped with the package: /usr/share/dasik/examples/
  Restoring \$HOME with config-saver happens AFTER the first boot — see
  https://github.com/$PKG_REPO#restoring-home
EOF
