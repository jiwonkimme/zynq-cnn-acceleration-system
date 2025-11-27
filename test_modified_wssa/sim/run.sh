#!/bin/bash

# 1. Generate Golden Reference Data
python3 ./matrix-hex/golden_gen.py

# 2. Compile
iverilog -o tb_mac_top.vvp \
    ../src/mac_1x1_unit.v \
    ../src/mac_4x1_col.v \
    ../src/mac_4x4_array.v \
    ../src/mac_top.v \
    ../src/bram_test.v \
    tb_mac_top.v

# 3. Check compilation status
if [ $? -eq 0 ]; then
    echo "Compilation Successful. Running Simulation..."
    # 4. Run Simulation
    vvp tb_mac_top.vvp
    
    # 5. Open Waveform (Optional)
    # gtkwave tb_mac_top.vcd &
else
    echo "Compilation Failed."
fi