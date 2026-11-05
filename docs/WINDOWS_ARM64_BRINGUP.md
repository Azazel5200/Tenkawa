# Windows ARM64 bring-up

This is a working checklist for the Windows port, not a claim that the game is
playable. The first milestone is a native **game-free bootstrap**. The original
European UMD release (`ULES-01456`) is needed only for later local installation
and runtime testing. No disc image, extracted executable, generated game code,
saves or captures belong in Git.

**Verified on 2026-11-04:** The game-free TenkawaNative bootstrap compiled and
its `--help` smoke test passed on Windows ARM64 (MSVC), Windows x64 (MSVC) and
Linux x64 (GCC) in [GitHub Actions run 41936870868](https://github.com/Azazel5200/Tenkawa/actions/runs/41936870868).
The **Vulkan renderer and shaders compiled** on native Windows ARM64 in
[run 41937884679](https://github.com/Azazel5200/Tenkawa/actions/runs/41937884679).
The relocatable graphics-linked package passed its `--help` smoke test in
[run 41940576348](https://github.com/Azazel5200/Tenkawa/actions/runs/41940576348).

**First hardware test on 2026-11-05:** The package installed a separately owned
`ULES-01456` disc image, initialized Vulkan 1.3 on a Qualcomm Adreno X1-45
under native Windows ARM64, and displayed the game's authentic PSP clock notice
and opening dialogs in interpreter mode. The next scene was black; the title
screen and gameplay are **not** established on Windows. See the measured
diagnosis below. Video playback and streamed music are unavailable in this
FFmpeg-disabled build.

## 1. Baseline: game-free native executable

The [native bootstrap workflow](../.github/workflows/ci.yml) builds the same
Tenkawa profile on Linux x64, Windows x64 and Windows ARM64. It disables the
renderer, FFmpeg and game-specific generated code, then checks that the native
executable accepts `--help` without starting the game. Passing this workflow
demonstrates that the host code can compile and link on that architecture; it
does **not** test rendering, playback or game execution.

For a local Windows ARM64 build, install Git, CMake 4.2 or newer, and Visual
Studio 2026 with its ARM64 C++ toolchain. From a developer PowerShell:

```powershell
git clone --recurse-submodules --branch dev/windows-arm64-bringup https://github.com/Azazel5200/Tenkawa.git
cd Tenkawa
cmake -S . -B out -G "Visual Studio 18 2026" -A ARM64 -DPORTABLEKIT_RENDERER=OFF -DPORTABLEKIT_FFMPEG=OFF -DPSPRECOMP_BUILD_TESTS=OFF -DPSPRECOMP_CCACHE=OFF
cmake --build out --target TenkawaNative --config Release --parallel 2
.\out\bin\Release\TenkawaNative.exe --help
```

The equivalent Windows x64 smoke build can use Visual Studio 2022 with
`-G "Visual Studio 17 2022" -A x64`. Match the generator to the Visual Studio
version actually installed. The bootstrap executable has **no graphical
renderer or media decoding by design**; do not use it to judge playability.

To refresh the framework submodule in an existing checkout, run
`git submodule update --init --recursive`. Normal submodule checkout uses the
commit pinned by Tenkawa; it does not silently pull a newer framework version.

## 2. Renderer and interpreter bring-up

The [Windows ARM64 Vulkan workflow](../.github/workflows/windows-arm64-renderer.yml)
also publishes a **game-free experimental ZIP** when all its checks pass. It
uses `PORTABLEKIT_RELEASE=ON` so the executable does not contain a fallback
path into the CI checkout. Download the artifact from that workflow's run
page while it is retained; unzip it into a new directory. The package includes
the native host, the SDL3/Vulkan loader dependencies and their license notices,
**not** the executable or assets from the PSP game. It has FFmpeg disabled and
should not be mistaken for a playable release.

1. Build a **separate** configuration with SDL3, the Vulkan SDK and
   `glslangValidator` available, and `-DPORTABLEKIT_RENDERER=ON`. Check that
   CMake explicitly reports `Vulkan renderer enabled`; otherwise the build is
   headless. FFmpeg is a separate dependency and must also be enabled before
   testing movie and music playback.
2. Install the user's own supported game image locally with
   `TenkawaNative --install path-to-image.iso`. The installer verifies the
   disc ID and hashes; do not alter those checks to accept a different build.
3. Run the **interpreter first** and verify its opening screens, display-list
   activity and input. Record logs and bounded performance measurements.
4. Only then generate and compile the AOT corpus. Compare the same scripted
   frame under interpreter and AOT to investigate the known missing GE display
   lists (see PortableKit issue #20). Do not assume a successful frame loop is
   proof that the image rendered.
5. Test audio, menu navigation, saves and actual gameplay separately. None of
   these are established by the bootstrap test.

The repository's `docs/MISSING.md` remains the authoritative record of
observed game-specific blockers. PortableKit's `docs/BUILDING.md` explains
why full corpus compilation needs significant RAM and limited parallelism.

## 3. Windows ARM64 black-scene diagnosis

The first real Windows ARM64 run used the **interpreter**, not the recompiled
AOT corpus. The Vulkan window rendered the initial clock and memory-stick
screens, then stayed black. Its 335 one-second performance samples recorded:

| Interval | Game speed | PSP display lists | Draw operations |
| --- | --- | --- | --- |
| First ~75 seconds | Mostly 100%, ~60 FPS | ~60/s | 74–175 per frame |
| Following ~260 seconds | Mostly 100%, ~60 FPS | ~60/s | 1 per frame |

The transition from 172 to 1 draw was sudden, and the remaining log contained
no Vulkan error or crash. This is **not evidence of a slow guest CPU**; it is
consistent with a game/GE scene that no longer submits useful geometry. Whether
it is waiting for I/O, receiving an incorrect HLE response, or intentionally
drawing a blank frame is still unknown. The missing `kirk.aes.38` warning is
not established as causal: the PGD check described in `MISSING.md` did not
require reading the PGD payload on the previously tested platform.

The next measurement is a bounded I/O trace across the transition to black.
The experimental package includes `collect_windows_trace.ps1` beside the
executable; run it in PowerShell after installing the game locally:

```powershell
.\collect_windows_trace.ps1
```

Its output goes to the local temporary `Tenkawa-Traces` directory. Reproduce
the initial prompts, leave the black screen for roughly one minute, close the
window and inspect the trace. The command enables performance and I/O logs.
For a subsequent **targeted** display-list trace, use
`-GeListStart N -GeListCount M` after determining the relevant list index;
do not dump every command of every frame. As an alternative when script
execution is disabled, the variables can be set manually before launching:

```powershell
$env:TENKAWA_TRACE_IO = '1'
$env:TENKAWA_PERF = 'log'
.\TenkawaNative.exe *> "$env:TEMP\tenkawa-io.txt"
```

Do not commit, upload or attach the original ISO, extracted game executable,
generated guest code or saves. Logs may contain local paths; review them
before sharing. The installation location is under
`%APPDATA%\Tenkawa\DBZTTT\`; it is distinct from the original ISO and may
contain saves that must be preserved before any later cleanup.

## 4. Older x64 hardware and legacy graphics

The eventual low-power x64 target needs its **own measurements** after a
playable native Windows build exists. PortableKit currently uses a Vulkan
renderer. Direct3D 9 or an older OpenGL path would require a separate graphics
backend and accuracy checks for PSP blending, framebuffers and texture
operations; changing the CMake generator or the output resolution does not
provide such a backend.

Measure CPU time, GPU time, memory use, frame pacing and graphics correctness
at the original PSP resolution first. Evaluate 720p only after the baseline
is stable. Do not claim a frame-rate improvement over PPSSPP without a
same-hardware, same-scene comparison.
