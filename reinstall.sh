#!/bin/sh
# Build the native helper, install it to $HOME/.dsh/cua/, and (re)install the bundle.
#
# Usage: ./reinstall.sh [profile] [spec]
#   profile  DSH profile name            (default: desktop)
#   spec     package spec to install     (default: the local tarball)
#            e.g. github:elfgzp/dsh-cua-macos
#
# The bundle must be installed as a packed tarball or a git spec: pnpm's `link:`
# protocol does not install a bundle's own dependencies, and @deepseek-ai/dsh-cua
# is not shipped with the DSH installation.
#
# Environment overrides for the helper download:
#   DSH_CUA_REPO         GitHub repository    (default: the `origin` remote of this
#                        checkout, else elfgzp/dsh-cua-macos)
#   DSH_CUA_HELPER_TAG   release tag or `latest` (default: latest)
#   DSH_CUA_NO_DOWNLOAD  set to 1 to always compile locally
set -e

here=$(cd "$(dirname "$0")" && pwd)
profile=${1:-desktop}
spec=${2:-}
dsh="/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh"

if [ ! -x "$dsh" ]; then
  echo "dsh CLI not found at $dsh" >&2
  exit 1
fi

# ---- 1. native helper -------------------------------------------------------
# The provider package ships Swift sources but no prebuilt helper, and the Loader
# only compiles inside a DSH source checkout. Resolve the helper here, in order:
#   1. a helper already committed/installed under native/bin/<platform>-<arch>/
#   2. the prebuilt binary attached to a GitHub Release by .github/workflows
#   3. a local `swift build`
# and keep a copy in $HOME/.dsh/cua/, which is where cordis.patch.yml points.
case "$(uname -m)" in
  arm64)  swift_arch=arm64;  helper_arch=arm64 ;;
  x86_64) swift_arch=x86_64; helper_arch=x86_64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
platform=darwin
asset="dsh-cua-native-$platform-$helper_arch"
built="$here/native/bin/$platform-$helper_arch/dsh-cua-native"

repo=${DSH_CUA_REPO:-}
if [ -z "$repo" ]; then
  origin=$(git -C "$here" remote get-url origin 2>/dev/null || true)
  case "$origin" in
    *github.com[:/]*) repo=$(printf '%s' "$origin" | sed -e 's|.*github\.com[:/]||' -e 's|\.git$||') ;;
  esac
fi
repo=${repo:-elfgzp/dsh-cua-macos}
tag=${DSH_CUA_HELPER_TAG:-latest}

download_helper() {
  if [ "${DSH_CUA_NO_DOWNLOAD:-0}" = "1" ]; then
    echo "==> download disabled by DSH_CUA_NO_DOWNLOAD"
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "==> curl not available"
    return 1
  fi

  base="https://github.com/$repo/releases"
  if [ "$tag" = "latest" ]; then
    url="$base/latest/download/$asset"
  else
    url="$base/download/$tag/$asset"
  fi
  echo "==> trying prebuilt helper: $url"

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/dsh-cua.XXXXXX") || return 1
  # shellcheck disable=SC2064 # expand $tmp now, while it is still in scope
  trap "rm -rf '$tmp'" EXIT HUP INT TERM

  if ! curl -fsSL --connect-timeout 10 --max-time 300 --retry 2 \
        -o "$tmp/$asset" "$url"; then
    echo "==> no prebuilt $asset at $url"
    return 1
  fi
  if [ ! -s "$tmp/$asset" ]; then
    echo "==> downloaded $asset is empty"
    return 1
  fi

  # The workflow publishes "<sha256>  <name>" next to the binary, which is what
  # `shasum -c` reads; verify before the binary is allowed anywhere near $HOME.
  if ! curl -fsSL --connect-timeout 10 --max-time 60 --retry 2 \
        -o "$tmp/$asset.sha256" "$url.sha256"; then
    echo "==> no checksum for $asset at $url.sha256; refusing to use an unverified download"
    return 1
  fi
  if ! (cd "$tmp" && shasum -a 256 -c "$asset.sha256"); then
    echo "==> sha256 verification FAILED for $asset; refusing to install it"
    return 1
  fi

  file "$tmp/$asset" | grep -q "Mach-O 64-bit executable $helper_arch" || {
    echo "==> downloaded $asset is not a Mach-O $helper_arch executable"
    return 1
  }

  mkdir -p "$(dirname "$built")"
  cp "$tmp/$asset" "$built"
  chmod 755 "$built"
  echo "==> prebuilt helper verified and cached at $built"
  return 0
}

if [ ! -x "$built" ]; then
  if ! download_helper; then
    echo "==> building native helper (swift $swift_arch); this needs Xcode or the Command Line Tools"
    xcrun swift build \
      --package-path "$here/native" \
      --scratch-path "$here/native/.build/runtime-$helper_arch" \
      --configuration release \
      --product dsh-cua-native \
      --arch "$swift_arch"
    mkdir -p "$(dirname "$built")"
    cp "$here/native/.build/runtime-$helper_arch/release/dsh-cua-native" "$built"
  fi
else
  echo "==> using existing helper at $built"
fi

mkdir -p "$HOME/.dsh/cua"
cp "$built" "$HOME/.dsh/cua/dsh-cua-native"
chmod 755 "$HOME/.dsh/cua/dsh-cua-native"
echo "==> helper installed to $HOME/.dsh/cua/dsh-cua-native"

# ---- 2. bundle ---------------------------------------------------------------
if [ -z "$spec" ]; then
  echo "==> packing bundle"
  cd "$here"
  npm pack --pack-destination "$here/dist" >/dev/null
  version=$(node -p "require('./package.json').version" 2>/dev/null || echo 0.1.0)
  spec="file:$here/dist/dsh-cua-macos-$version.tgz"
fi

echo "==> removing previous install of dsh-cua-macos"
"$dsh" plugin --profile "$profile" remove dsh-cua-macos || true

echo "==> installing $spec"
"$dsh" plugin --profile "$profile" add "$spec"

echo "==> done. Restart DSH to apply the new layer, then start a new session."
