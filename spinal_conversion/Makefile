
all: verilog

verilog:
	sbt "runMain usb.MyTopLevelVerilog"

clean:
	rm -rf simWorkspace
	rm -rf tmp
	rm -rf target
	rm -rf *.v
	rm -rf IP

.PHONY: verilog clean
