# What is missing

What this port does not have yet, most blocking first. Everything here was measured, not guessed: the import lists come from the game's own import table, the recompiler's gaps from the code it generated, and the boot failures from running the game.

Platform for the original results below: macOS on Apple Silicon, Vulkan through
MoltenVK. The independently measured Windows ARM64 result is noted separately.

## Where the port is

**The game boots to its opening screens and loads its data.** It starts, runs its threads, reads the disc, sets up audio, draws its clock-frequency notice, takes a button press, runs its memory-stick check, and then opens and streams the files it needs. With the recompiled corpus linked its frame loop holds **30 frames per second at 100% speed**.

**It reaches its title screen.** Captured from the corpus-free build, in order: the clock-frequency notice with its "next page" triangle, "Checking Memory Stick. Please do not turn off power." after the confirm button, a white screen while it loads, and then the title — the logo, the four characters, the dragon balls, the two copyright lines and a blinking "Press START button". Everything on it is drawn correctly: gradients, outlined text, the alpha on the blinking prompt. No captures are kept in this repository, because they are made from the game's own art.

**Only the corpus-free build draws.** The recompiled build executes **one display list in a whole run** where the interpreter executes one per frame, so it presents nothing and its window is black. That is [PortableKit#20](https://github.com/TeamGDB/PortableKit/issues/20) and it is the thing to fix before anything else here can be judged by looking at it. An earlier note in this file said the game draws with the corpus linked; that was the frame loop running, not the drawing.

### Windows ARM64 gameplay milestone (2026-11-06)

A later Windows 11 ARM64 interpreter run **reached the title, navigated the
menus, entered a battle and reached the defeat/results screen**. This was
observed on real Qualcomm Adreno X1-45 hardware, with the separately owned
European disc image and a private, fingerprint-verified six-key PGD file.
The four sampled PGD ioctl requests all returned `0x00000000` instead of the
earlier repeated `0x80010005`. The previous black-screen observation below is
now a **resolved interpreter start-up blocker**, not the current limit.

The sampled combat interval had 414 one-second performance records: **23.5
host FPS on average**, 16.0 minimum, 31.3 maximum, and 70 records below
20 FPS. Average guest execution took **34.3 ms**; Vulkan render took **3.0 ms**
and measured GPU work **2.8 ms**. The game remains too slow in interpreter
mode; CPU-side PSP interpretation is the dominant measured cost. This run had
**no AOT corpus installed**, so it does not establish the speed or correctness
of recompiled ARM64 code.

Attack/effect audio was audible, but streamed music was not. The bootstrap
was intentionally built with `PORTABLEKIT_FFMPEG=OFF`, and its stdout said
`Audio: built without FFmpeg; streamed music is silent`. The game displayed
English despite its multilingual disc: the profile had not specified a PSP
system language. Graphics also show character trails and misaligned results
text; neither is diagnosed from traces yet.

**Next blockers:** build and compare the AOT corpus on ARM64 (the earlier
macOS missing-display-list problem must be tested, not assumed fixed), enable
native ARM64 FFmpeg to test low-level ATRAC music, then investigate the
remaining graphics inaccuracies. No user game data or crypto keys are part
of the repository or CI artifacts.

### Windows ARM64 interpreter observation (2026-11-05)

The game-free Vulkan build from the Windows ARM64 development branch was used
with a separately owned `ULES-01456` disc. On Windows 11 ARM64 with a Qualcomm
Adreno X1-45, the interpreter rendered the original PSP clock notice and the
memory-stick screens correctly. After the two confirmations, the window became
black before the title screen. No recompiled corpus was present, so this is
**not the same observation** as the AOT display-list issue above.

The first captured run has 335 one-second performance samples. For about 75
seconds the host presented ~60 frames and ~60 GE display lists per second,
with between 74 and 175 draw operations per frame. Thereafter, for 260 seconds,
the game still reported almost 100% speed and ~60 lists per second, but only
**one draw operation per frame**. The transition happened between consecutive
samples, with no Vulkan error or process crash in the trace. This proves that
the window was presenting frames; it does **not** prove that the scene logic
was progressing or explain why no useful geometry was submitted.

**Historical follow-up:** a bounded I/O trace found repeated PGD ioctl
failures. Installing a private, verified key file for the later run resolved
the repeated failures and the interpreter reached gameplay (see above).
The separate AOT graphics issue is still open. Do not commit player disc
data, generated code, captures, saves, keys or identifying paths.

It was not stuck before; it was waiting, and three things were in the way. They are worth writing down in order, because the first one cost a day and was not a missing system call at all.

**1. It was waiting for the player.** The screen it sits on is the game's own message box — the clock-frequency notice, with the yellow "next page" triangle in the corner. Its scene is a three-state machine whose handler table is at `0x08A804D0`: state 0 plays a twenty-frame fade-in, **state 1 (`0x08a2f688`) reads the pad and does nothing at all until the confirm button is pressed**, state 2 leaves. Behind that scene, a disc-check module the game loads from `disc0:/sce_lbn0xec21_size0x2480` and runs at `0x08A81660` waits for the scene to finish (`0x08a2f9dc` is "state == -1"), which is what made everything downstream look frozen.

Nobody had pressed a button. `TENKAWA_INPUT_SCRIPT="600:pad a;700:pad a"` gets past it.

**2. `sceUtilitySavedata` mode 22, GETSIZE.** Past the notice the game runs its memory-stick check and asks GETSIZE for `ULES01456`/`DAT0`, `DAT1` and `DAT2`. The framework answered a parameter error for every mode it did not implement, and the game put up a message dialog and stayed there. It is answered now, from the same three size blocks SIZES uses.

**3. Neither of the two things this looked like.** Both of the earlier conclusions were wrong, and both were expensive:

- The PGD file the game opens was fully worked out and verified ([PortableKit#17](https://github.com/TeamGDB/PortableKit/issues/17)) — and the game never reads it. The module opens it, hands the driver a key through `sceIoIoctl` command `0x04100001`, closes it again, and that is the whole check.
- The `umd1:` device commands `0x01F300A5`/`0x01F300A7` ([PortableKit#19](https://github.com/TeamGDB/PortableKit/issues/19)) are a read-ahead, and answering them changes nothing: the game reads a zero result from the second one as "finished", which is what the framework already returned. Byte for byte the same run with and without them.

### Where it gets to now

After two presses it reads the gzip stream at `sce_lbn0xec27` — the range the read-ahead asks for — re-opens the PGD file three more times, opens `sce_lbn0xec3d`, `sce_lbn0xec5b` and `sce_lbn0xed2a`, starts ATRAC through `sceAtracGetAtracID`, `sceAtracLowLevelInitDecoder` and `sceAtracLowLevelDecode`, and streams `sce_lbn0x3eb50_size0x13E790` in 608-byte pieces for as long as it is left running. The three ATRAC calls are logging stubs, so it is being fed silence.

Under the interpreter the white screen lasts about 1100 frames, because the load runs about twenty times slower than the game expects. The recompiled build, which would load it in seconds, draws nothing.

**At the time of the original macOS test:** anything past the title screen,
START input, sound or the recompiled title screen was unverified. The later
Windows ARM64 interpreter gameplay milestone above supersedes the first two
limitations, but not the audio or AOT questions.

## What the game asks of the GE

Now that it draws, this is answerable, and the port answers it itself: the GE reports every command it ignored at the end of a run. Over ~25,900 frames it ignored **60 distinct commands**, every one of them with a value of zero:

| Commands | Times | 
| --- | --- |
| `0x15`, `0x16`, `0x1c`, `0x20`, `0x25`, `0x26`, `0x28`, `0x38`, `0xe8`, `0xe9` | once per frame |
| `0x24`, `0x27` | twice per frame |
| `0x2c`–`0x33`, `0x36`, `0x37`, `0x50`, `0xa1`–`0xaf`, `0xb9`–`0xc1`, `0xc8`, `0xca`, `0xcc`, `0xd0`, `0xd8`–`0xdd`, `0xe2`–`0xe6` | once or twice in the whole run |

The shape of that is worth reading carefully before implementing anything. The long tail of once-in-the-run commands with a zero value is the game clearing state it never uses, and the per-frame group is a fixed preamble it writes every list. **Nothing here has been shown to affect what is drawn** — the screens it does draw are correct. This list is a starting point for when something draws wrongly, not a list of bugs.

### What has been implemented to get here


Nine framework calls and two framework fixes, each one found by running the game and reading what it stopped on. None of them mentions this game:

| What | Why it was in the way |
| --- | --- |
| `sceKernelExtendThreadStack` | Must call the function it is given; stubbed, `module_start` returned without creating the game's main thread |
| Lightweight mutexes (create/delete, lock/unlock) | Used throughout start-up |
| `sceKernelCheckThreadStack` | Returning 0 says the stack is exhausted, and the game believes it |
| `sceKernelMemcpy` | Returning without copying corrupts what was to be copied |
| `sceDisplayWaitVblankStart` ×3, `sceDisplayGetVcount` | Nothing paced the frame loop, so it spun |
| Raw disc device, in sectors | The game reads `PACKFILE.BIN` straight off the disc |
| The game-data install dialog | It polled the dialog's status for ever; it now completes (without copying, which is said aloud) |
| The UMD and power callbacks | Registered during start-up |
| Six instructions: `vrndi`, `vi2s`, `vt5650`, `vi2uc`, `vrndf1`, `addi` | Neither the recompiler nor the interpreter could execute them |
| Kernel mailboxes | Created during start-up; the kernel had no such primitive |
| `sceAudioOutput2*`, `sceAudioOutputBlocking` | The audio thread runs at priority 0x10; not blocking starved the other two |
| User partition sized from guest RAM | The stack landed outside RAM on a 32 MiB console |
| Module info without section names | No imports at all, so no HLE at all |

## 1. System calls the game makes that are not implemented

**45 of the 228 imports**, and this is the executable's own answer, not an inference from reading the framework's source: run the port with `TENKAWA_LIST_STUBS=1` and it prints exactly this. Each one is bound to a logging stub that prints the call once and returns 0, and a stub that returns 0 is a lie the game acts on.

| Library | Missing | Notes |
| --- | --- | --- |
| `sceNetAdhocMatching` (11 of 11) | `Init`, `Term`, `Create`, `Delete`, `Start`, `Stop`, `SelectTarget`, `CancelTargetWithOpt`, `SetHelloOpt`, `SendData`, `AbortSendData` | The whole peer-matching library. The first port's game did its own matchmaking over `sceNetAdhocctl` and never touched it. [PortableKit#9](https://github.com/TeamGDB/PortableKit/issues/9) |
| `sceSasCore` (9 of 27) | `__sceSasSetADSR`, `SetADSRmode`, `SetSL`, `SetGrain`, `GetGrain`, `SetNoise`, `SetOutputmode`, `GetAllEnvelopeHeights`, `GetPauseFlag` | The mixer's envelope, grain and noise control. The game calls `GetAllEnvelopeHeights` during start-up. [PortableKit#7](https://github.com/TeamGDB/PortableKit/issues/7) |
| `sceUtility` (6 of 21) | The five `sceUtilityGamedataInstall*` calls, and `sceUtilityGetSystemParamString` | The shell's data-install dialog. [PortableKit#10](https://github.com/TeamGDB/PortableKit/issues/10) |
| `sceAtrac3plus` (4 of 5) | `sceAtracLowLevelInitDecoder`, `sceAtracLowLevelDecode`, `sceAtracGetAtracID`, `sceAtracReinit` | This game feeds the decoder raw frames rather than handing it a file. **All four are now called** — the first three as soon as it gets past its opening screens — so this is the next thing in the way. [PortableKit#8](https://github.com/TeamGDB/PortableKit/issues/8) |
| `sceNetAdhocctl` (4 of 12) | `Connect`, `Join`, `GetState`, `GetPeerInfo` | Joining and creating a group |
| `ThreadManForUser` (3 of 31) | `sceKernelWaitSemaCB`, `sceKernelWaitThreadEnd`, `sceKernelWaitThreadEndCB` | The callback-polling forms of waits that do exist |
| `sceUmdUser` (3 of 5) | `sceUmdRegisterUMDCallBack`, `UnRegister…`, `sceUmdWaitDriveStatCB` | Disc-change callbacks. The game registers one during start-up |
| `sceMpeg` (2 of 23) | `sceMpegAvcDecode`, `sceMpegAvcDecodeStop` | AVC video decode proper |
| `IoFileMgrForUser` (1 of 9) | `sceIoIoctl` | The other half of raw UMD access. Not reached yet |
| `sceImpose` (1 of 2) | `sceImposeSetUMDPopup` | Called during start-up and the game carries on regardless |
| `scePower` (1 of 4) | `scePowerUnregisterCallback` | Same |

Of these, only four are known to be called at all so far: `sceImposeSetUMDPopup`, `sceUmdRegisterUMDCallBack`, `sceAtracReinit` and `__sceSasGetAllEnvelopeHeights`. The rest are what the executable imports, which is not the same as what it uses.

## 2. The recompiler

**The whole executable now lowers.** 8579 function seeds, 488049 code addresses, 153 C++ units, in about two and a half minutes. The only sites the recompiler cannot lower are the game's own 41 `break` instructions, which are its assertion traps and are correct as they are.

It did not start that way. 435 sites came out unsupported, and one of them — `0xD03CA084` at `0x0882EAD4` — is where the port stopped, because the interpreter could not execute it either. They turned out to be six distinct instructions, all now implemented in the framework:

| Instruction | Sites | What it does |
| --- | --- | --- |
| `vrndi` | 359 | A random 32-bit pattern per element |
| `vi2s` | 16 | The top halfword of each element, two per destination word |
| `vt5650` | 8 | Packed 8888 colours to 5650 |
| `vi2uc` | 6 | A quad of integers to four bytes — **the one the port stopped on** |
| `vrndf1` | 1 | A random float in [1, 2) |
| `addi` | 4 | Add immediate. `addiu` was lowered; this was not |

One of those is not faithful and is worth knowing about. The VFPU's random generator keeps its state in the control registers RCX0..RCX7, and the PSP's own sequence is not documented anywhere this project can use, so the framework substitutes its own: deterministic, and explicitly not what hardware produces. This game draws from it 359 times and never calls `vrnds` to seed it, so whatever the framework starts with decides every one of those draws. Expect anything driven by it — scattering, timing jitter, idle animation — to differ from a PSP. It will not fail; it will look different.

## 3. Graphics

Answered above, from the game's own display lists.

## 4. Save data

The game writes `ms0:/PSP/SAVEDATA/ULES01456/…` and `ULES01456INST/DATAINST.BIN`. The framework implements the PSP save-data format — the `PARAM.SFO` layout, the encryption of the data file and the hashes that protect it — so saves should be exchangeable with a PSP. **Unverified:** no save has been made or read, the data file's name is not known, and whether this game encrypts its save at all has not been checked.

## 5. Not verified at all

- Anything on Linux or Windows. Everything here is macOS on Apple Silicon.
- Speed. The game's frame loop advances, but it draws nothing, so the numbers mean nothing yet. Guest time ran about 20,000x faster than real time in a headless run, which is what a loop with no work in it and no renderer to throttle it looks like.
- The ad hoc product code in the profile is a guess; the game's own is not known.
- That the game has no code overlays. The profile declares none. It does, however, load and run **one module off the disc at run time**: `disc0:/sce_lbn0xec21_size0x2480` is a PSP ELF with a fixed load address of `0x08A81660`, and the game reads its header, its one program header and its 9072 bytes by hand and jumps into it. The recompiler never sees it, so it runs interpreted; that is correct and costs nothing, but it is not the same as "no overlays".
