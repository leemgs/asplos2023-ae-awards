#!/bin/bash

# Gathers simulation times for Calyx interprer, Verilog, and Icarus-Verilog.
# Example:
#   PROGRAM="examples/futil/dot-product.futil"
#      DATA="examples/dahlia/dot-product.fuse.data"
#      FILE="dot-product.csv"
# INTERVALS=10
  PROGRAM=$1
     DATA=$2
     FILE=$3
INTERVALS=$4

echo "[RUNNING] interpreter simulation: $PROGRAM"

# Gather Calyx interpreter simulation times.
for (( i = 0; i < $INTERVALS; ++i ))
do
    fud e $PROGRAM --to interpreter-out -s verilog.data $DATA \
    -pr interpreter.interpret -csv -q \
    >> $FILE
done

# # Gather Calyx debuigger simulation times.
# for (( i = 0; i < $INTERVALS; ++i ))
# do
#     fud e $PROGRAM --to debugger -s verilog.data $DATA -s interpreter.debugger.flags "-p "\
#     -pr interpreter.interpret -csv -q \
#     >> $FILE
# done

echo "[COMPLETE] interpreter simulation: $PROGRAM"
echo "[RUNNING] iverilog compilation and simulation: $PROGRAM"

# Gather Icarus-Verilog simulation times.
for (( i = 0; i < $INTERVALS; ++i ))
do
    fud e $PROGRAM --to dat -s verilog.data $DATA --through icarus-verilog -s futil.flags "-x tdcc:no-early-transitions" \
    -pr icarus-verilog.simulate icarus-verilog.compile_with_iverilog -csv -q \
    >> $FILE
done

echo "[COMPLETE] iverilog compilation and simulation: $PROGRAM"
echo "[RUNNING] verilog compilation and simulation: $PROGRAM"

# Gather Verilog simulation times.
for (( i = 0; i < $INTERVALS; ++i ))
do
    fud e $PROGRAM --to dat --through verilog -s verilog.data $DATA -s futil.flags "-x tdcc:no-early-transitions" \
    -pr verilog.simulate verilog.compile_with_verilator -csv -q \
    >> $FILE
done

echo "[COMPLETE] verilog compilation and simulation: $PROGRAM"
