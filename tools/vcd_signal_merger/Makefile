BUILD_DIR := build

.PHONY: all clean compile

all: compile

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/CMakeCache.txt: $(BUILD_DIR)
	cd $(BUILD_DIR) && cmake ..

compile: $(BUILD_DIR) $(BUILD_DIR)/CMakeCache.txt
	cd $(BUILD_DIR) && cmake --build . -j $(shell nproc)

clean:
	rm -rf $(BUILD_DIR)
