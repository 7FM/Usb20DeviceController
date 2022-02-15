#!/bin/sh
#TEST_PATH=./sim_build/top/Vsim_top
#TEST_PATH=./sim_build/usb_rx/Vsim_usb_rx
TEST_PATH=./sim_build/usb_tx/Vsim_usb_tx
#TEST_PATH=./sim_build/trans_fifo_tb/Vsim_trans_fifo_tb
RUNS=10000
THREADS=$(nproc)

j=0
i=0
N=$THREADS
while [ $j -le $RUNS ]; do
    ((i=i%N)); ((i++==0)) && wait
    $TEST_PATH 2>&1 -s $RANDOM | grep "FAILED" &
    j=$(( j + 1 ))
done
