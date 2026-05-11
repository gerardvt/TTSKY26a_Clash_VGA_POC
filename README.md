![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# TTSKY26a Clash VGA PoC

A [Tiny Tapeout](https://tinytapeout.com) project targeting the `ttsky26a` shuttle (Sky130A PDK), authored in [Clash HDL](https://clash-lang.org) — a Haskell-based hardware description language that compiles to Verilog.

- [Project datasheet](docs/info.md)

---

## Purpose

This project is a **proof of concept for using Clash HDL as a Tiny Tapeout design entry language**, not a showcase of a sophisticated hardware design. The goal is to work through all the scaffolding required to take a Clash-based design through the full TT submission pipeline end-to-end:

- Setting up a Cabal project that builds the Clash compiler as a local executable
- Compiling Clash source to Verilog and wiring it into the TT source file layout
- Configuring CI workflows (`test`, `docs`, `gds`) to build Clash on every push with effective caching
- Resolving integration issues with the TT VGA Playground (see below)

The design — an interactive triangle-wave plasma effect — is intentionally simple. It was chosen as a convenient vehicle for exercising the full submission workflow, including all eight input pins, rather than as an end in itself. The infrastructure and lessons documented here provide a reusable foundation for future, more ambitious Clash-based TT entries.

---

## Design: interactive triangle-wave plasma

The design generates a full-screen animated plasma on VGA 640×480 @ 60 Hz using triangle-wave approximations of sine functions (no lookup table). Three overlapping waves at different spatial angles combine into a single plasma value, which is mapped to 2-bit RGB with 120-degree phase offsets, giving 64 colours.

All eight input pins are active. The controls are **independent bit fields** — multiple pins may be high simultaneously and each takes effect concurrently.

```
  bit:  7   6   5   4   3   2   1   0
        |palette|inv|  speed  |pattern|pause
         [7:6]   [5] [4:3]   [2:1]    [0]
```

| `ui_in` | Field | Values |
|---|---|---|
| `[0]` | **pause** | 1 = freeze animation, 0 = run |
| `[2:1]` | **pattern** | `00` = three-wave plasma (default) · `01` = two-wave (h+v) · `10` = diagonal waves · `11` = XOR plasma |
| `[4:3]` | **speed** | Frame counter step: `00`=×1 · `01`=×2 · `10`=×4 · `11`=×8 |
| `[5]` | **invert** | 1 = complement plasma value before colour mapping |
| `[7:6]` | **palette** | `00` = RGB 120° offsets (default) · `01` = shifted hue · `10` = fire · `11` = greyscale |

**Example values:**

| `ui_in` | Effect |
|---|---|
| `0x00` | Default: three-wave plasma, speed ×1, RGB palette |
| `0x01` | Frozen at current frame |
| `0x06` | Two-wave pattern (`[2:1] = 01`) |
| `0x18` | Speed ×4 (`[4:3] = 10`) |
| `0x20` | Inverted colours |
| `0xC0` | Greyscale palette (`[7:6] = 11`) |
| `0xFF` | All controls active: XOR plasma, speed ×8, inverted, greyscale, frozen |

Pause freezes the frame counter regardless of speed — pattern, invert, and palette still render at the frozen frame.

---

## VGA Playground integration

Tiny Tapeout creates a project page for each registered design (e.g. `app.tinytapeout.com/projects/NNNN`). That page includes a **VGA Playground: Open** link which opens a simulation at a URL of the form:

```
https://vga-playground.com/?repo=https://github.com/[owner]/[repo]&ref=[commit-sha]
```

The `ref` is the exact commit SHA that TT captured when "Submit a new revision" was last clicked on the project page. The playground then:

1. Fetches `info.yaml` from the repo at that specific commit
2. Reads the `source_files` list
3. Fetches each listed file from `src/` at the same commit SHA via the GitHub raw content API

**The problem — generated Verilog is not committed**

The Verilog that feeds the playground (`gvt_core.v`) is produced by the CI workflow on every run. Standard practice is to gitignore generated build artefacts and never commit them. This means `gvt_core.v` does not exist in the repo at any commit SHA, and the playground gets a 404 when it tries to fetch it.

This is a chicken-and-egg situation: the playground needs the compiled Verilog to simulate the design, but the correct practice for CI-generated files is to not commit them — they are always regenerated from the Clash source on each build.

**The compromise**

In this submission repo, `src/gvt_core.v` is **removed from `.gitignore` and committed** alongside the Clash source. The CI still regenerates it on every workflow run (overwriting the committed copy), so it always reflects the current source. When "Submit a new revision" is clicked on the TT project page, TT captures the HEAD SHA at that point — a commit that includes `gvt_core.v` — and the playground can fetch it successfully.

The trade-off is that `gvt_core.v` appears as a tracked file even though it is a build artefact. This is a deliberate compromise specific to this submission repo, where playground compatibility takes priority over the usual practice of gitignoring generated files.

---

## Design language: Clash HDL

Clash is a functional hardware description language that uses Haskell as its host language and compiles to synthesisable Verilog or VHDL. It provides a strong static type system, higher-order functions, and composable abstractions that are difficult to express in traditional HDLs.

### How the build works

```
clash/src/Top.hs        →   cabal exec clash   →   build/Top.topEntity/tt_um_gerardvt_clash_poc.v
clash/src/VgaTiming.hs  ↗                                        │
                                                                  └── cp ──► src/gvt_core.v
```

`src/gvt_core.v` is generated on every CI run. The Clash top entity is named `tt_um_gerardvt_clash_poc` directly — no separate Verilog shim file is needed.

To build locally:

```bash
scripts/build-clash.sh
```

To clean all build artefacts:

```bash
scripts/clean.sh
```

---

## Project structure

```
clash/
  vga-colorbars.cabal   # Cabal project (library + clash compiler exe)
  bin/Main.hs           # Clash compiler entry point (boilerplate)
  src/
    VgaTiming.hs        # Shared VGA timing module
    Top.hs              # Interactive plasma effect — imports VgaTiming
  build/                # Clash Verilog output — gitignored
  dist-newstyle/        # Cabal build artefacts — gitignored

src/
  gvt_core.v            # Generated by Clash — committed for VGA Playground

scripts/
  build-clash.sh        # Rebuild Clash and regenerate src/gvt_core.v
  clean.sh              # Remove all gitignored build artefacts

test/
  tb.v                  # Cocotb testbench
  test.py               # Test logic
  Makefile              # Runs iverilog + cocotb

.github/workflows/
  docs.yaml             # Validates info.yaml + docs/info.md
  test.yaml             # RTL simulation via cocotb
  gds.yaml              # Full OpenLane GDS build
  fpga.yaml             # FPGA flow (disabled)
```

---

## VGA timing modularisation

`VgaTiming.hs` exports a `VgaTiming` record and a `vgaTiming` function that any future Clash design on this project can import, avoiding duplication of the counter and sync-generation logic.

---

## CI workflows

All three active workflows (`test`, `docs`, `gds`) follow the same structure:

1. Setup GHC 9.6.7 and Cabal
2. Restore Cabal cache
3. Build the Clash compiler (`cabal build exe:clash`)
4. Generate Verilog (`cabal exec clash -- --verilog -isrc Top -outputdir build`)
5. Copy generated Verilog to `src/gvt_core.v`
6. Run the workflow-specific step (cocotb tests / docs check / OpenLane GDS)

### Caching strategy

Two caching problems were encountered and solved:

**Problem 1 — `clash-ghc` recompiled on every run (~7 min)**

Initially only `~/.cabal/store` (the downloaded package store) was cached. Even with a warm store, Cabal still had to recompile the `clash-ghc` executable on every run because `clash/dist-newstyle/` (the compiled output) was not cached.

**Solution:** Cache both `~/.cabal/store` and `clash/dist-newstyle/` together under the same key (hash of `vga-colorbars.cabal`). With a warm cache, the Clash build step drops from ~7 minutes to ~30 seconds.

**Problem 2 — Hardcoded Verilog output path**

The Clash output path was hardcoded in all workflows. Clash resolved to a different version in CI than locally and placed the output in a different subdirectory, breaking the `cp` step.

**Solution:** Use `find . -name 'tt_um_gerardvt_clash_poc.v' | head -1` to locate the generated file regardless of where Clash puts it.

---

## Potential CI improvements

### 1. Reusable workflow for the Clash build steps

The Clash build steps (GHC setup, cache restore, `cabal build`, `cabal exec clash`) are duplicated across `test.yaml`, `docs.yaml`, and `gds.yaml`. A reusable workflow (`workflow_call`) could extract these into a single definition that all three call.

**Why not done yet:** Low urgency now that the `dist-newstyle` cache is in place and each build is fast. Deferred to keep the change surface small.

### 2. Build Clash once per push, share the result

All three workflows run in parallel on every push, each independently building Clash and generating `gvt_core.v`. Ideally Clash would build once and the generated file would be shared across all three as a workflow artifact.

Two approaches were considered:

**Option A — Single workflow file with `needs:`**
Move all jobs (`clash-build`, `test`, `docs`, `gds`, etc.) into one workflow file. The `clash-build` job generates `gvt_core.v` as an artifact and all other jobs declare `needs: clash-build` to download it before running. Clash runs exactly once per push.

*Why not done:* The TT submission portal almost certainly gates submissions on specific workflow names (`gds`, `docs`) existing and passing. Consolidating into a single file would lose those names and potentially break submission validation. This needs to be confirmed before implementing.

**Option B — Cross-workflow dependencies via `workflow_run`**
Keep the separate workflow files and trigger `test`, `docs`, `gds` from a `clash-build` workflow using the `workflow_run` event.

*Why not done:* `workflow_run` triggers execute in the context of the repository's **default branch** (`main`), not the branch that was pushed. This would cause `test`, `docs`, and `gds` to check out `main`'s code instead of the pushed branch — breaking everything for feature branches. Workarounds exist (explicitly reading `github.event.workflow_run.head_sha`) but add significant complexity.

---

## Running tests locally

Install dependencies once:

```bash
# GHC and Cabal (via ghcup)
ghcup install ghc 9.6.7 && ghcup set ghc 9.6.7

# Python test dependencies
pip install -r test/requirements.txt

# Icarus Verilog
# macOS with oss-cad-suite: already included
# Ubuntu: sudo apt-get install -y iverilog
```

Build and test:

```bash
scripts/build-clash.sh          # generate src/gvt_core.v
cd test && make clean && make   # run cocotb tests
```

Test results are written to `test/results.xml`. Waveforms are dumped to `test/tb.fst` (viewable with GTKWave or Surfer).

> **Note:** The above covers RTL simulation only. Running the docs validation and GDS build locally requires further integration with the tooling provided by [TinyTapeout/tt-support-tools](https://github.com/TinyTapeout/tt-support-tools). This has not yet been tested and is deferred for a future update.
