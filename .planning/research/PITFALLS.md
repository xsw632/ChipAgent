# Pitfalls Research

**Domain:** Chisel/RTL Automation Pipeline
**Researched:** 2026-03-16

## Critical Pitfalls

### 1. Verilator WIDTH warnings on Chisel-generated Verilog
**Warning signs:** `%Warning-WIDTH` in Verilator lint output
**Prevention:** Chisel generates Verilog with automatic width inference that Verilator may flag. Use `/* verilator lint_off WIDTH */` pragmas or waiver files for known-safe patterns.
**Phase:** Phase 3 (Hooks/Linting)

### 2. firtool not found despite Chisel 6.0+ auto-management
**Warning signs:** `firtool not found in PATH` during compilation
**Prevention:** Chisel 6.0+ auto-downloads firtool, but first run may be slow. Ensure CHISEL_FIRTOOL_PATH is set if custom version needed. The sbt `run` task handles this automatically.
**Phase:** Phase 1 (Project Setup)

### 3. Hook infinite loops
**Warning signs:** Hook triggers compilation → writes file → triggers hook again
**Prevention:** Use precise `matcher` patterns (match specific file extensions, not all Write/Edit). Only trigger on `.scala` files, not on generated `.v` files.
**Phase:** Phase 3 (Hooks)

### 4. Verilator C++ testbench clock handling
**Warning signs:** Simulation hangs or produces incorrect results
**Prevention:** Verilator requires manual clock toggling in C++ testbench. Must call `eval()` after each input change and toggle clock explicitly.
**Phase:** Phase 2 (TB Generator skill)

### 5. sbt first-run download time
**Warning signs:** Pipeline appears stuck during first execution
**Prevention:** Run `sbt compile` once during setup to cache all dependencies. Document this in setup instructions.
**Phase:** Phase 1 (Project Setup)

### 6. LLM generating syntactically invalid Chisel
**Warning signs:** sbt compilation errors on generated code
**Prevention:** The 3-attempt auto-fix loop addresses this. Include Chisel coding patterns in skill prompts. Use concrete examples in skill templates.
**Phase:** Phase 2 (Skills)

### 7. npm package path resolution after installation
**Warning signs:** `${CLAUDE_PLUGIN_ROOT}` paths don't resolve
**Prevention:** All hook scripts must use `${CLAUDE_PLUGIN_ROOT}` for paths. Never use absolute paths. Test with `claude --plugin-dir` during development.
**Phase:** Phase 4 (Integration)

---
*Pitfalls research for: Chisel/RTL Automation Pipeline*
*Researched: 2026-03-16*
