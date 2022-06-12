# Tool Overview

## Annotation Reader

- parse PulseView USB annotations
- useless as cli tool

## TLA to VCD

- parse Tektronix TLA5000 `*.txt` data exports and create a VCD file

### Usage: 
```
tla_to_vcd -i <input_file.txt> -o <output.vcd>
```

## VCD Annotation Masking

- uses the annotation reader in combination with a VCD file to mask out the signals produced by the USB device

### Usage: 
```
vcd_annotation_masking -i <input_file.vcd> -a <annotations_of_input_file> -o <output.vcd>
```

## VCD Concat

- concatenate a given list of vcd files while patching the timestamps accordingly
- Note that all files have to use the same signal names!

### Usage:
```
vcd_concat -i <input1.vcd> -i <input2.vcd> [-i <inputN.vcd>] -o <output.vcd> 
```

## VCD Real Thresholder

- calculate the average signal value of real signals
- the average is used as threshold to binarize the real signals
&rarr; convert analog samples to digital values

### Usage:
```
vcd_real_thresholder -i <input.vcd> -o <output.vcd>
```

## VCD Signal Merger

- kind of the inverse of `vcd_annotation_masking`: but requires both the traces of the device and host signals
- merges the specified signals with the given operator (`-A` for `&&` or `-O` for`||`) 

### Usage:
```
vcd_signal_merger -i <input.vcd> -o <output.vcd> -O "USB_DN;USB_DN_OUT" -A "USB_DP;USB_DP_OUT" -t
```

## VCD Time to CLK

- convert a VCD file, which correctly uses the timescale and timestamps to match a certain clock frequency, to an invalid VCD file where the timescale is ignored and every tick corresponds to one clock cycle
- this is especially required for VCD files used with `sim_vcd_replay`!

### Usage:
```
vcd_time_to_clk -i <input.vcd> -o <output.vcd> -s "12MHz" -t 4
```
