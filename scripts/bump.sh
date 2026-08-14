#!/usr/bin/env bash
# Cut a new dasik package version.
#
#   scripts/bump.sh 0.2.0          # -> pkgver=0.2.0 pkgrel=1, tag 0.2.0
#   scripts/bump.sh 0.2.0 2        # -> pkgver=0.2.0 pkgrel=2, tag 0.2.0-2
#   scripts/bump.sh 0.2.0 --push   # ...and push main + the tag
#
# Pushing the tag is what triggers .github/workflows/build.yml, which builds
# the package and publishes it as a release asset. The ISO bootstrap installs
# that asset, so "cut a version" and "the ISO gets it" are the same act.
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \?//'; exit "${1:-1}"; }

push=0
args=()
for arg in "$@"; do
    case "$arg" in
        --push) push=1 ;;
        -h|--help) usage 0 ;;
        -*) echo "unknown flag: $arg" >&2; usage ;;
        *) args+=("$arg") ;;
    esac
done

[ "${#args[@]}" -ge 1 ] || usage
pkgver="${args[0]}"
pkgrel="${args[1]:-1}"

cd "$(dirname "$0")/.."
[ -f PKGBUILD ] || { echo "PKGBUILD not found — run this from the repo" >&2; exit 1; }

# A version that is not a valid pkgver would break makepkg in the CI job
# instead of here, where the message is useful.
[[ "$pkgver" =~ ^[0-9][A-Za-z0-9._+]*$ ]] || {
    echo "invalid pkgver: $pkgver (letters, digits, . _ +; must start with a digit)" >&2
    exit 1
}
[[ "$pkgrel" =~ ^[0-9]+$ ]] || { echo "invalid pkgrel: $pkgrel" >&2; exit 1; }

[ -z "$(git status --porcelain)" ] || {
    echo "working tree is dirty — commit or stash first" >&2
    exit 1
}

# The PKGBUILD pins the *upstream* tag. Bumping to a tag that does not exist
# yet produces a release whose every install fails at `git checkout`, so refuse
# early rather than publish a broken package.
url="$(sed -n 's/^url="\(.*\)"$/\1/p' PKGBUILD)"
if ! git ls-remote --exit-code --tags "$url.git" "refs/tags/$pkgver" > /dev/null 2>&1; then
    echo "upstream tag '$pkgver' does not exist at $url" >&2
    echo "create it first:  git -C ../dasik tag $pkgver && git -C ../dasik push origin $pkgver" >&2
    exit 1
fi

sed -i "s/^pkgver=.*/pkgver=$pkgver/; s/^pkgrel=.*/pkgrel=$pkgrel/" PKGBUILD

if command -v makepkg > /dev/null 2>&1; then
    makepkg --printsrcinfo > .SRCINFO
else
    echo "warning: makepkg not found, .SRCINFO left stale" >&2
fi

tag="$pkgver"
[ "$pkgrel" = "1" ] || tag="$pkgver-$pkgrel"

git add PKGBUILD .SRCINFO
git commit -m "Bump to $pkgver-$pkgrel"
git tag "$tag"

if [ "$push" = "1" ]; then
    git push origin HEAD "$tag"
    echo "pushed. The release job is building: $url-aur/actions"
else
    echo "done. Publish with:  git push origin HEAD $tag"
fi
