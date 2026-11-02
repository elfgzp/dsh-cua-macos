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
# only compiles inside a DSH source checkout. Build it here and keep a copy in
# $HOME/.dsh/cua/, which is where cordis.patch.yml points.
case "$(uname -m)" in
  arm64)  swift_arch=arm64;  helper_arch=arm64 ;;
  x86_64) swift_arch=x86_64; helper_arch=x64   ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

built="$here/native/bin/darwin-$helper_arch/dsh-cua-native"
if [ ! -x "$built" ]; then
  echo "==> building native helper (swift $swift_arch)"
  xcrun swift build \
    --package-path "$here/native" \
    --scratch-path "$here/native/.build/runtime-$helper_arch" \
    --configuration release \
    --product dsh-cua-native \
    --arch "$swift_arch"
  mkdir -p "$(dirname "$built")"
  cp "$here/native/.build/runtime-$helper_arch/release/dsh-cua-native" "$built"
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
