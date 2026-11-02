# dsh-cua-macos

macOS Computer Use for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness):
the agent reads accessibility trees, captures screenshots and drives real desktop
apps — the same capability shape as Anthropic's computer use, as a DSH plugin.

> This is **not** an official DeepSeek package. The official bundle
> `@deepseek-ai/dsh-cua-bundle` exists, but it only ships on the `0.2.2-alpha`
> channel and cannot be installed on a `0.2.1-rc.5` profile. See
> [Why a local bundle](#why-a-local-bundle).

## Status

| | |
| --- | --- |
| Platform | macOS on Apple silicon or Intel, DSH **Host** only |
| DSH version | `0.2.1-rc.5` (pinned; the alpha line needs `0.2.2-alpha.2`) |
| Requires | macOS Accessibility + Screen Recording permission for the DSH process |
| Tool name | `cua` |

## Why a local bundle

The official `@deepseek-ai/dsh-cua-bundle`:

- ships only on the `0.2.2-alpha` channel, which requires cordis `~4.0.6-alpha.1`
  while a `0.2.1-rc.5` profile runs cordis `4.0.5`;
- expects a prebuilt native helper that the published npm tarball does not carry
  ("installed packages must already carry their native payload" — upstream defers
  helper distribution to the packaged Desktop app).

The three component packages *are* published on both lines, so this bundle mounts
the same rows at the versions that match the shipped runtime, and builds the
missing helper locally.

| Row | Package | Role |
| --- | --- | --- |
| `cua-provider-registry` | `@deepseek-ai/dsh-computer-use` | the exclusive computer-use provider slot |
| `cua` | `@deepseek-ai/dsh-experimental-cua-macos` | macOS native provider: AX tree, screenshots, input |

`@deepseek-ai/dsh-cua` is **not** mounted as its own row: at `0.2.1-rc.5` it
exports only `CuaConfig` and `installCua`, with no `apply`, so the Loader cannot
mount it as a plugin. The macOS provider imports it as a library and calls
`installCua`, which registers the `cua` tool and the model guidance. The
`0.2.2-alpha` line does export an `apply` and does need its own row.

`@deepseek-ai/dsh-attachment` and `@deepseek-ai/dsh-user-questions` are listed as
ordinary dependencies because `@deepseek-ai/dsh-cua` imports them at runtime and
the Loader resolves them from the profile, not from the DSH installation.

## Install

```sh
git clone https://github.com/elfgzp/dsh-cua-macos.git
cd dsh-cua-macos
./reinstall.sh
```

`reinstall.sh` resolves the native helper, installs it to
`$HOME/.dsh/cua/dsh-cua-native`, packs the bundle and installs it into the
profile. Restart DSH afterwards and start a **new** session.

Xcode is only needed when no prebuilt helper is available: `reinstall.sh`
downloads the arm64 or x86_64 binary from the GitHub Release first and compiles
from source only if that fails. See [Prebuilt helper](#prebuilt-helper).

The bundle must be installed as a tarball or a git spec. pnpm's `link:` protocol
does not install a bundle's own dependencies, so a linked checkout would leave
`@deepseek-ai/dsh-cua` unresolvable.

To install from this repository instead of a local tarball:

```sh
./reinstall.sh desktop github:elfgzp/dsh-cua-macos
```

## The native helper

`@deepseek-ai/dsh-experimental-cua-macos` ships the Swift sources of the
`dsh-cua-native` helper but no binary, and the Loader only compiles inside a DSH
source checkout. `reinstall.sh` therefore resolves it, in this order:

1. a helper already present under `native/bin/<platform>-<arch>/`;
2. the prebuilt binary attached to a GitHub Release (see
   [Prebuilt helper](#prebuilt-helper));
3. a local compile:

```sh
xcrun swift build \
  --package-path native \
  --scratch-path native/.build/runtime-arm64 \
  --configuration release \
  --product dsh-cua-native \
  --arch arm64
```

The result is copied to `$HOME/.dsh/cua/dsh-cua-native`, which is where
`cordis.patch.yml` points it through a `!!js` expression — so the patch itself
stays machine-independent.

Only step 3 requires Xcode or the Command Line Tools. The package declares
`swift-tools-version: 6.0`, but the vendored sources need **Swift 6.3 or newer**
to compile in the Swift 6 language mode; with an older toolchain the build stops
at `sending 'self' risks causing data races` in `SharedHelperServer.swift`. On a
machine without a recent enough toolchain, step 2 is what makes the install work.

### Prebuilt helper

`.github/workflows/build-helper.yml` builds the helper in CI and attaches it to
the GitHub Release for a `v*` tag:

| Asset | Runner | Build command |
| --- | --- | --- |
| `dsh-cua-native-darwin-arm64` (+ `.sha256`) | `macos-26` (arm64) | `swift build --arch arm64` |
| `dsh-cua-native-darwin-x86_64` (+ `.sha256`) | `macos-26` (arm64) | `swift build --arch x86_64` |

Both are cross-compiled on the arm64 runner, so the workflow does not depend on
GitHub's hosted Intel images, which are being retired; the x86_64 binary is a
real `Mach-O 64-bit executable x86_64` and is exercised through Rosetta 2 in CI.
The image is pinned to Xcode 26.6 (Swift 6.3.3) because the Swift 6.2 toolchain
on the older `macos-15` image rejects this vendored source with `sending 'self'
risks causing data races`; the workflow fails with an explicit message if the
runner ever offers only an older Swift.

Each binary is ad-hoc signed (`codesign --force --sign - --identifier
dsh-cua-native`), the same way a local `swift build` on macOS produces it, so the
CI artifact and a locally compiled helper are interchangeable.

The workflow also runs on `workflow_dispatch` and on every pull request; those
runs build and verify the helper but do **not** publish, so a broken build is
caught before a tag is cut. `swift test` is not part of CI: the suite drives real
Accessibility and ScreenCaptureKit APIs and needs a logged-in GUI session with
both permissions granted, which a hosted runner does not provide. CI instead
smoke-tests that the binary executes and can parse its command-line options,
which happens before any AX call.

`reinstall.sh` uses the release assets when it finds no local helper:

```sh
./reinstall.sh            # downloads dsh-cua-native-darwin-<arch> for this Mac
```

It picks `latest` by default; to pin a tag, or to skip the download entirely,
use the environment overrides:

```sh
DSH_CUA_HELPER_TAG=v0.1.0 ./reinstall.sh   # a specific release
DSH_CUA_REPO=you/dsh-cua-macos ./reinstall.sh  # a fork
DSH_CUA_NO_DOWNLOAD=1 ./reinstall.sh       # always compile locally
```

The download is verified with the published `.sha256` and by checking the Mach-O
header against the host architecture. A missing release, a missing checksum or a
mismatch is reported explicitly and `reinstall.sh` falls back to compiling from
source — it never installs an unverified binary and never silently skips the
helper.

`native/` is vendored from `@deepseek-ai/dsh-experimental-cua-macos`; see
`native/upstream.json` for the per-file provenance and `native/LICENSE.cua-driver`
for the upstream license.

## System permissions

macOS asks the process that runs DSH for two permissions:

- **Accessibility** — to read the accessibility tree and post input events.
- **Screen Recording** — to capture screenshots.

Grant both in *System Settings → Privacy & Security*. At `0.2.1-rc.5` there is no
permission page in the Plugin Manager, so do it by hand; the `0.2.2-alpha` line
adds a page with one-click navigation.

Per-application authorization is requested by the agent at first use and stored in
the profile's domain storage, so grants survive restarts.

## How the tool reaches an agent

`@deepseek-ai/dsh-experimental-cua-macos` mounts at host level, so its
`ctx.tools.register({ name: "cua" })` lands in the **global** tool layer rather
than an agent scope. `ToolRuntime.view(scope)` starts every agent scope's view
from `layers.global.tools`, and nothing in the agent, preset or permission
packages calls `tools.restrict()`, so the `cua` tool is visible to every new
session.

A session created *before* the plugin was installed keeps its recorded tool
scope, so it will not see `cua`; start a new session after restarting DSH.

## What the agent can do

The `cua` tool exposes one method per operation:

| Group | Methods |
| --- | --- |
| Discovery | `getCapabilities`, `listApps`, `findApps`, `getApp`, `activate`, `show`, `listWindows` |
| Observation | `getState` (accessibility tree), `screenshot` |
| Interaction | `click`, `hover`, `typeText`, `pressKey`, `setValue`, `selectText`, `paste`, `scroll`, `drag`, `performSecondaryAction` |

Clicks and hovers accept either an element index from the last `getState` read or
a coordinate — absolute pixels from the last screenshot, or `relative: true`
thousandths of the window size. Actions return `dispatched: true, verified:
false`, so the agent has to read fresh state to confirm an action landed.

## Reading the accessibility tree

`getState` returns the tree for one application. Two things about its shape are
worth knowing:

- **The top-level `windowId` can be `null`.** For an app without a normal
  window (Finder is one), the useful ids live in the `windows[]` array instead —
  pass one of those to `screenshot`. Windows with `isOnScreen: false` still
  capture correctly.
- **The tree is application-scoped, not window-scoped.** For Finder that means
  the menu-bar items plus an `AXScrollArea` named "桌面" (disabled) that holds
  the desktop's own elements. Menu-bar contents are omitted unless you pass
  `includeMenus: true`.

## Application approval

The first time a task selects an application, the Host asks the human:

> Allow Computer Use to launch if needed, read, capture, and control <app>?

with **Allow for this task**, **Deny** and **Always allow** (the last one only
when the app identity is persistable). The answer is per session unless it is
saved, and a saved grant lives in the provider's `allowedApps` config.

This prompt needs a human answerer, so it only works in a foreground session —
a delegated task (subagent, workflow agent) gets `APP_APPROVAL_UNAVAILABLE`
instead and must be handed back to the main task.

## Quirks found in live use

**Empty `params` objects.** Some models (MiniMax M3.1-Flash among them) encode an
empty JSON object in a tool call as the *string* `"{}"`. The `cua` schema requires
`params` to be an object, so those calls fail with:

```
[{"expected":"object","code":"invalid_type","path":["params"],"message":"Invalid input: expected object, received string"}]
```

`params` methods that require no arguments (`getCapabilities`, `listApps`) also
reject a non-empty object, because their schema is strict-empty. The way through
is a key that adds no own property: `{"method": "getCapabilities", "params": {"__proto__": 1}}`.
Models that emit proper JSON objects never hit this.

**`getApp` needs a foreground task.** Selecting an application triggers a
per-application authorization prompt, which is only available in a foreground
session. A delegated task (subagent, workflow agent) gets:

```
APP_APPROVAL_UNAVAILABLE: Application approval is unavailable in delegated tasks; ask the main task to perform this operation
```

So `listApps`, `getCapabilities` and the other read-only methods work anywhere,
but the first `getApp` for an app has to run in the main session.

## Known limitations

- Windows support is in development upstream; this bundle is macOS only.
- No permission page in the Plugin Manager at `0.2.1-rc.5`.
- The committed artifact under `native/bin/` is arm64 only; Intel Macs get the
  `x86_64` helper from the GitHub Release, or compile it with `./reinstall.sh`.
- The `cua` tool is not scoped to a PTC preset at `0.2.1-rc.5`. The alpha line
  moves it into the PTC generated SDK.

## Attribution

Native helper sources are adapted from [trycua/cua](https://github.com/trycua/cua)
(`cua-driver-rs-v0.28.0`), MIT licensed.

## License

MIT — see [LICENSE](LICENSE).
