# Building LyricBubbles from source

This page is for developers. To just use the app, [download it](https://github.com/jeff3-dev/LyricBubbles/releases/latest) instead.

## What you need

- macOS 15 (Sequoia) or later.
- Xcode 16 or later, or the matching Command Line Tools (Swift 5.10+ with the macOS 15 SDK).

There are no third-party dependencies. The project is a plain Swift package (no Xcode project).

## Get the code and build it

```bash
git clone https://github.com/jeff3-dev/LyricBubbles.git
cd LyricBubbles
./build.sh              # builds LyricBubbles.app (release) in the repo folder
open LyricBubbles.app
```

## Commands

```bash
swift build             # debug build
swift test              # run the test suite
./build.sh              # release LyricBubbles.app next to the script
./build.sh --install    # also copies it to /Applications and opens it
./build.sh --dist       # universal (arm64 + x86_64) build, packed into dist/*.dmg and dist/*.zip
```

Set `VERSION` and `BUILD` at the top of `build.sh` before packaging a release.

Settings are stored in the app's user defaults (`local.lyricbubbles`).
