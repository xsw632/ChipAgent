# def2gds.py - KLayout DEF-to-GDS merge for nangate45
#
# Merges a routed DEF file with nangate45 standard cell GDS to produce
# a final GDS stream-out. Invoked by pnr.sh via:
#   klayout -zz -rd design_name=... -rd in_def=... ... -r def2gds.py
#
# Variables passed via KLayout -rd flags:
#   design_name - top module name (e.g., ALU)
#   in_def      - path to routed DEF file
#   tech_lef    - path to tech LEF
#   cell_lef    - path to cell LEF
#   in_gds      - path to nangate45 standard cell GDS
#   out_file    - path to output GDS file

import pya
import sys
import os

# --- Load DEF with LEF context ---
# CRITICAL: Use LEF files via layoutOptions, NOT .lyt tech file
# (tech file produces dummy macros without real geometry)
layoutOptions = pya.LoadLayoutOptions()
layoutOptions.lefdef_config.lef_files = [tech_lef, cell_lef]

main_layout = pya.Layout()
main_layout.read(in_def, layoutOptions)

top_cell_index = main_layout.cell(design_name).cell_index()

# --- Clear orphan cells (preserve VIA_ cells from DEF) ---
for i in main_layout.each_cell():
    if i.cell_index() != top_cell_index:
        if not i.name.startswith("VIA_"):
            i.clear()

# --- Merge standard cell GDS ---
main_layout.read(in_gds)

# --- Copy to clean output layout ---
top_only_layout = pya.Layout()
top_only_layout.dbu = main_layout.dbu
top = top_only_layout.create_cell(design_name)
top.copy_tree(main_layout.cell(design_name))

# --- Verify all cells have geometry ---
errors = 0
for i in top_only_layout.each_cell():
    if i.is_empty():
        print(f"[ERROR] Empty cell: {i.name}")
        errors += 1

# --- Write output GDS ---
top_only_layout.write(out_file)
file_size = os.path.getsize(out_file)
print(f"GDS written: {out_file} ({file_size} bytes)")

sys.exit(errors)
