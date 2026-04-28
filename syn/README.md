# DDR3 Controller Synthesis Directory

## Prerequisites

- Synopsys Design Compiler (DC) or DC Ultra
- Standard cell library (e.g., TSMC 28nm, GlobalFoundries 22nm)
- Update library paths in `dc/setup.tcl` before running

## Directory Structure

```
syn/
├── README.md             # This file
├── dc/
│   ├── setup.tcl         # DC library/search-path setup
│   ├── read_design.tcl   # RTL file read script
│   ├── constraints.tcl   # Timing/area/DRC constraints (400 MHz)
│   ├── compile.tcl       # Top-level DC compile script
│   └── reports/
│       ├── timing_summary.txt   # Estimated timing targets
│       ├── area_summary.txt     # Estimated area breakdown
│       └── bandwidth_calc.txt   # Theoretical bandwidth analysis
├── constraints/
│   └── ddr3_ctrl_top.sdc # SDC timing constraints
├── lint/
│   └── verilator_lint.sh # Verilator lint runner
└── reports/              # (placeholder for generated reports)
```

## Running Synthesis

```bash
# 1. Set up environment
source /path/to/dc/setup.sh

# 2. Launch DC
dc_shell -f dc/compile.tcl | tee dc/reports/compile.log

# 3. View reports
cat dc/reports/timing_summary.txt
cat dc/reports/area_summary.txt
```

## Design Targets

| Metric          | Target        |
|-----------------|---------------|
| Clock frequency | 400 MHz       |
| Technology      | 28nm CMOS     |
| Core area       | ~0.05 mm²     |
| WNS             | ≥ 0 ps        |
| Power           | < 20 mW       |

## Notes

- Reports in `dc/reports/` are **design targets**, not actual tool output
- Actual synthesis requires a licensed DC installation and standard cell library
- Run `lint/verilator_lint.sh` first to catch RTL issues before synthesis
