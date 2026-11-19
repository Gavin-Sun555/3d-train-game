APP_NAME := traingame3d
PROJECT_DIR := $(CURDIR)

.PHONY: build run demo editor data check clean

## build: 默认目标，仅生成数据、静态编译校验脚本与着色器并生成可执行启动器（不自动运行游戏）
build: data/grid_city.json data/seattle_expanded.json data/tram_models.json
	godot --headless --path . --import
	@out=$$(godot --headless --path . --quit 2>&1); \
	echo "$$out"; \
	if echo "$$out" | grep -q "SCRIPT ERROR:"; then exit 1; fi
	cc -O2 -Wall -Wextra -DPROJECT_DIR='"$(PROJECT_DIR)"' tools/launcher.c -o $(APP_NAME)
	@echo "Build complete -> ./$(APP_NAME) (run 'make run' or './$(APP_NAME)' to start)"

data/grid_city.json data/seattle_expanded.json data/tram_models.json: tools/extract_demo_data.py
	python3 tools/extract_demo_data.py

## run: 编译并启动游戏（进入主页选择地图）
run: build
	./$(APP_NAME)

## demo: 编译并直接进入西雅图示例线网试驾
demo: build
	./$(APP_NAME) --map seattle --demo

## editor: 用 Godot 4 编辑器打开项目
editor:
	godot --editor --path .

## data: 强制重新生成地图与车辆数据
data:
	python3 tools/extract_demo_data.py

## check: 无头静态编译与资源导入检查
check:
	godot --headless --path . --import
	godot --headless --path . --quit

## clean: 清理编译产物
clean:
	rm -f $(APP_NAME)
