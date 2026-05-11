---
name: chipyard-rtl
description: "Generate Verilog RTL from a local Chipyard installation. Elaborates a Rocket Chip config (e.g. TinyRocketConfig) and produces split Verilog files with memory configuration."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# chip-agent:chipyard-rtl

Generate Verilog RTL from a local Chipyard installation by elaborating a Rocket Chip configuration.

## Usage

```
/chip-agent:chipyard-rtl [--chipyard <path>] [--config <ConfigName>] [--output <dir>]
```

**Defaults:**
- `--chipyard`: `/home/mingzhenjia/Desktop/chipyard` (or first argument as bare path)
- `--config`: `TinyRocketConfig`
- `--output`: `<chipyard>/sims/verilator/generated-src/<package>.harness.TestHarness.<Config>/gen-collateral/`

**Examples:**

```
/chip-agent:chipyard-rtl
/chip-agent:chipyard-rtl /home/user/chipyard
/chip-agent:chipyard-rtl --config RocketConfig
/chip-agent:chipyard-rtl --chipyard /opt/chipyard --config TinyRocketConfig
```

## Instructions

**Determine the project root directory** by finding the nearest ancestor directory of this skill file that contains `.claude`. Use that directory as the base for all relative paths below.

## Pipeline

### Step 0 -- Parse Arguments

Parse `$ARGUMENTS` to extract:

| Flag | Default | Description |
|------|---------|-------------|
| `--chipyard <path>` | `/home/mingzhenjia/Desktop/chipyard` | Path to local Chipyard repository |
| `--config <name>` | `TinyRocketConfig` | Chisel config class name |
| `--output <dir>` | auto-determined | Output directory override |

If no flags are provided and `$ARGUMENTS` is a bare path that exists as a directory, treat it as `--chipyard`.

Validate:
```bash
test -d "$CHIPYARD_DIR"
test -f "$CHIPYARD_DIR/build.sbt"
```

If Chipyard directory is invalid, STOP with:
```
Chipyard not found at <path>.
Provide a valid Chipyard root directory with --chipyard <path>.
```

### Step 1 -- Verify Environment

Set up environment variables:

```bash
CHIPYARD_DIR="<parsed chipyard path>"
CONFIG="<parsed config name>"

# Detect RISCV toolchain location
if [ -d "$CHIPYARD_DIR/.conda-env/riscv-tools" ]; then
    export RISCV="$CHIPYARD_DIR/.conda-env/riscv-tools"
elif [ -n "$RISCV" ]; then
    : # already set
else
    echo "ERROR: RISCV not set and no .conda-env/riscv-tools found"
    exit 1
fi

# Set Java
export JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8"
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
export PATH="$JAVA_HOME/bin:$PATH"

# Add conda env bin to PATH for firtool and other tools
if [ -d "$CHIPYARD_DIR/.conda-env/bin" ]; then
    export PATH="$CHIPYARD_DIR/.conda-env/bin:$PATH"
fi

# Verify firtool
which firtool || echo "WARNING: firtool not found in PATH"
```

Verify key tools exist:
```bash
which sbt
which firtool
java -version
```

If `sbt` or `firtool` is missing, STOP with a clear message explaining what's needed.

### Step 2 -- Validate Config

Check that the requested config exists:

```bash
grep -r "class $CONFIG\b" "$CHIPYARD_DIR/generators/" --include="*.scala" -l
```

If not found, list available configs:
```bash
grep -r "class \w\+Config extends Config" "$CHIPYARD_DIR/generators/chipyard/src/main/scala/config/" --include="*.scala" -h | sed 's/class /  - /;s/ extends.*//'
```

STOP with: `Config '<ConfigName>' not found. Available configs listed above.`

### Step 3 -- Generate Verilog

Run the Chipyard Verilog generation:

```bash
cd "$CHIPYARD_DIR/sims/verilator" && \
make verilog CONFIG="$CONFIG" 2>&1 | tail -50
```

**Timeout:** This step may take 10-30 minutes depending on config complexity. Use a generous timeout (600000ms).

**Error handling:**
- If `firtool: command not found`: Add `$CHIPYARD_DIR/.conda-env/bin` to PATH and retry
- If `RISCV is unset`: Export `RISCV=$CHIPYARD_DIR/.conda-env/riscv-tools` and retry
- If sbt compilation fails: Show the error and suggest `cd $CHIPYARD_DIR && sbt --batch "compile"` to diagnose

### Step 4 -- Locate Output Artifacts

After successful generation, locate the output directory:

```bash
GEN_DIR="$CHIPYARD_DIR/sims/verilator/generated-src/chipyard.harness.TestHarness.$CONFIG/gen-collateral"
```

Verify key files:
```bash
test -d "$GEN_DIR" && echo "Output: $GEN_DIR"
ls "$GEN_DIR"/*.sv | wc -l      # count generated Verilog files
test -f "$GEN_DIR/ChipTop.sv"    # DUT top module
```

### Step 5 -- Summarize Results

Present a summary to the user:

```
=== Chipyard RTL Generation Complete ===

Config:       <ConfigName>
Output:       <GEN_DIR>
Files:        <N> Verilog/SystemVerilog files
Top module:   ChipTop

Key modules:
  - ChipTop.sv           (top-level SoC)
  - Rocket.sv            (Rocket core)
  - RocketTile.sv        (tile wrapper)
  - ICache.sv            (instruction cache)
  - DCache.sv            (data cache)

Memory config:
  <GEN_DIR>/../chipyard.harness.TestHarness.<Config>.mems.conf
```

Additionally, display the contents of `*.mems.conf`:

```bash
cat "$CHIPYARD_DIR/sims/verilator/generated-src/chipyard.harness.TestHarness.$CONFIG/chipyard.harness.TestHarness.$CONFIG.mems.conf"
```

### Step 6 -- Copy to ChipAgent Workspace (Helper Staging)

This helper skill may be used by `/chip-agent:chipyard` to stage generated RTL into ChipAgent's canonical workspace for downstream PnR:

```bash
PROJECT_ROOT="<project-root>"
DEST="$PROJECT_ROOT/MyDesign/$CONFIG/workspace/generated"
mkdir -p "$DEST"

# Concatenate all SV files into a single Verilog file (ORFS-friendly)
cat "$GEN_DIR"/*.sv > "$DEST/${CONFIG}.v"
echo "Copied to: $DEST/${CONFIG}.v"
```

Ask the user: "Copy generated RTL to ChipAgent workspace for PnR?" using AskUserQuestion with Yes/No options.

## Pipeline Stages

| # | Stage | Description |
|---|-------|-------------|
| 0 | Parse Arguments | Extract chipyard path, config name, output dir |
| 1 | Verify Environment | Check sbt, firtool, Java, RISCV toolchain |
| 2 | Validate Config | Confirm config class exists in Scala sources |
| 3 | Generate Verilog | Run `make verilog CONFIG=<name>` in Chipyard |
| 4 | Locate Output | Find and verify generated collateral directory |
| 5 | Summarize | Display generation results and memory config |
| 6 | Copy (Optional) | Copy RTL to ChipAgent workspace for downstream PnR |

## Input

$ARGUMENTS

Optional flags:
- `--chipyard <path>` -- Chipyard repository root (default: `/home/mingzhenjia/Desktop/chipyard`)
- `--config <ConfigName>` -- Chisel config class (default: `TinyRocketConfig`)
- `--output <dir>` -- Override output directory

Or a bare path as the first argument (treated as `--chipyard`).

## Output

Upon completion:
- Generated Verilog files in `<chipyard>/sims/verilator/generated-src/chipyard.harness.TestHarness.<Config>/gen-collateral/`
- Memory configuration in `<chipyard>/sims/verilator/generated-src/chipyard.harness.TestHarness.<Config>/*.mems.conf`
- Optionally copied to `MyDesign/<Config>/workspace/generated/<Config>.v`

## Anti-Patterns

- DO NOT run `make` without setting `RISCV` environment variable
- DO NOT skip environment verification -- Chipyard requires specific Java, sbt, and firtool versions
- DO NOT use `make -j` with parallel jobs -- sbt manages its own parallelism
- DO NOT assume conda activation works from a subshell -- directly set `PATH` to `.conda-env/bin`
