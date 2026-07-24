include toolchain.mk

APP := last-best-hope
BUILD_DIR := build
DIST_DIR := dist
TOOLS_DIR := .tools
ZELDA_ENGINE_ROOT ?= ../zelda-engine
ZELDA_ENGINE_PACKAGES := $(abspath $(ZELDA_ENGINE_ROOT))/packages
ZELDA_ENGINE_COLLECTION := -collection:zelda_engine=$(ZELDA_ENGINE_PACKAGES)

LOCAL_ODIN := $(TOOLS_DIR)/odin/$(ODIN_VERSION)/odin
LOCAL_SLANGC := $(TOOLS_DIR)/slang/$(SLANG_VERSION)/slangc
ODIN ?= $(LOCAL_ODIN)
SLANGC ?= $(LOCAL_SLANGC)
ODINFMT ?= odinfmt
CC ?= cc
AR ?= ar

ifeq ($(shell uname -s),Darwin)
HOMEBREW_LLVM_PREFIX := $(shell brew --prefix $(LLVM_HOMEBREW_FORMULA) 2>/dev/null)
ODIN_CLANG_PATH ?= $(HOMEBREW_LLVM_PREFIX)/bin/clang
export ODIN_CLANG_PATH
endif

DEV_DIR := $(BUILD_DIR)/dev
RELEASE_DIR := $(BUILD_DIR)/release
PROFILE_DIR := $(BUILD_DIR)/profile
TEST_DIR := $(BUILD_DIR)/test
GENERATED_DIR := $(BUILD_DIR)/generated
DEV_APP := $(DEV_DIR)/$(APP)
RELEASE_APP := $(RELEASE_DIR)/$(APP)
PROFILE_APP := $(PROFILE_DIR)/$(APP)
LEGACY_DEV_APP := $(BUILD_DIR)/$(APP)
LEGACY_PROFILE_APP := $(BUILD_DIR)/$(APP)-instrumented

ODIN_SOURCES := $(shell find src packages -type f -name '*.odin' 2>/dev/null)
ENGINE_SOURCES := $(shell find $(ZELDA_ENGINE_PACKAGES) -type f -name '*.odin' 2>/dev/null)
BUILD_INPUTS := $(ODIN_SOURCES) $(ENGINE_SOURCES) Makefile toolchain.mk

TEXTSHAPE_LIBS = $(shell pkg-config --libs harfbuzz freetype2)
COMMON_ODIN_FLAGS := $(ZELDA_ENGINE_COLLECTION)
DEV_ODIN_FLAGS ?= -debug -o:minimal
# A matched local build on the reference Apple Silicon machine completed the
# default single-module speed build faster than separate modules (117.6 s
# versus approximately 125 s). It also preserves cross-package optimization.
RELEASE_ODIN_FLAGS ?= -o:speed
PROFILE_ODIN_FLAGS ?= $(RELEASE_ODIN_FLAGS) -debug -keep-temp-files

TEST_OPT ?= speed
TEST_THREADS ?= 1
TEST_COMPILER_THREADS ?= 2
TEST_SEED ?= 24301
TEST_FLAGS := -o:$(TEST_OPT) -thread-count:$(TEST_COMPILER_THREADS) \
	-define:ODIN_TEST_THREADS=$(TEST_THREADS) \
	-define:ODIN_TEST_RANDOM_SEED=$(TEST_SEED)

GAME_TEST_FILES := $(wildcard tests/game/*.odin)
CANVAS_TEST_FILES := $(wildcard $(ZELDA_ENGINE_PACKAGES)/canvas2d/*.odin)
SRC_TEST_FILES := $(wildcard src/*.odin)
GAME_BALANCE_TEST_FILES := tests/game/close_engagement_balance_tests.odin
GAME_GENERATIVE_TEST_FILES := \
	tests/game/fleet_generator_integration_tests.odin \
	tests/game/fleet_skirmish_tests.odin \
	tests/game/galaxy_tests.odin \
	tests/game/persistence_tests.odin \
	tests/game/procedural_ship_tests.odin \
	tests/game/ship_generator_goal_tests.odin \
	tests/game/ship_generator_tests.odin \
	tests/game/solar_system_tests.odin \
	tests/game/stellar_system_tests.odin
SRC_GENERATIVE_TEST_FILES := \
	src/bot_validation_reporting.odin \
	src/ship_generator_closed_architectures_tests.odin \
	src/ship_generator_saucer_tests.odin \
	src/ship_generator_single_hull_tests.odin \
	src/ship_generator_ui_tests.odin \
	src/ship_recipe_tests.odin \
	src/ship_visual_tests.odin
GAME_FAST_TEST_FILES := $(filter-out $(GAME_BALANCE_TEST_FILES) $(GAME_GENERATIVE_TEST_FILES),$(GAME_TEST_FILES))
SRC_FAST_TEST_FILES := $(filter-out $(SRC_GENERATIVE_TEST_FILES),$(SRC_TEST_FILES))

BALANCE_RUNS ?= 150
BALANCE_SEED ?= 77
COMBAT_AI_CHECKPOINT ?= var/combat-ai-league-v3.json
COMBAT_AI_REPORT ?= var/combat-ai-league-v3-trials.json
COMBAT_AI_TRIAL_RUNS ?= 44
COMBAT_AI_TRIAL_BLOCKS ?= 4
COMBAT_AI_TRIAL_SEED ?= 900001
COMBAT_AI_WORKERS ?= 8
COMBAT_AI_HOURS ?= 8
COMBAT_AI_RUNS ?= 44
COMBAT_AI_SEED ?= 24301
MODULE_SIZE_TARGET ?= 700
MODULE_SIZE_HARD_LIMIT ?= 1200

ifeq ($(shell uname -s),Darwin)
LINKER_PLATFORM_FLAGS := -Wl,-no_warn_duplicate_libraries -framework Cocoa
endif

link_flags = $(TEXTSHAPE_LIBS) -L$(abspath $(1)) -lgfx_signposts -lc++ $(LINKER_PLATFORM_FLAGS)

UI_SHADER := assets/shaders/ui.slang
COMBAT_3D_SHADER := assets/shaders/close_engagement_3d.slang
COMBAT_NEBULA_SHADER := assets/shaders/close_engagement_nebula.slang
COMBAT_DEBRIS_SHADER := assets/shaders/close_engagement_debris.slang
SHADER_NAMES := \
	ui.vert.spv ui.frag.spv ui-post.vert.spv ui-post.frag.spv \
	close_engagement_3d.vert.spv close_engagement_3d.frag.spv \
	close_engagement_contact.vert.spv close_engagement_terrain.vert.spv \
	close_engagement_terrain.frag.spv close_engagement_background.vert.spv \
	close_engagement_background.frag.spv close_engagement_nebula.vert.spv \
	close_engagement_nebula.frag.spv close_engagement_debris.vert.spv \
	close_engagement_debris.frag.spv
GENERATED_SHADERS := $(addprefix $(GENERATED_DIR)/shaders/,$(SHADER_NAMES))

ASSET_PATHS := \
	assets/fonts/Iosevka-Regular.ttf \
	assets/fonts/NotoSansSymbols2-Regular.ttf \
	assets/fonts/ZeldaSans-Regular-v1.otf \
	assets/fonts/ZeldaSerif-Regular-v0_1.otf \
	assets/icons/ui-icon-atlas-garden.png \
	assets/icons/depth-planes-strip.png \
	assets/ships/ship-components-engraved.png \
	assets/ships/ship-components-map.png \
	assets/ships/ship-damage-atlas.png \
	assets/ships/ship-engine-effects-atlas.png \
	assets/ships/ship-markings-atlas.png \
	assets/ships/combat-archetype-icons-atlas-v1.png

.PHONY: all bootstrap doctor build release profile-build instrumented-build run demo passage agent bot simulate \
	fmt check check-module-size test test-all test-fast test-game test-canvas test-src \
	test-balance test-generative validate-balance combat-ai-overnight combat-ai-trials \
	package package-macos package-linux clean clean-tools

all: build

bootstrap:
	./tools/bootstrap-macos.sh

doctor:
	@set -eu; \
	fail=0; \
	check_command() { command -v "$$1" >/dev/null 2>&1 || { echo "error: missing $$1" >&2; fail=1; }; }; \
	check_command pkg-config; check_command "$(CC)"; check_command "$(AR)"; check_command "$(ODINFMT)"; \
	if [ "$$(uname -s)" = Darwin ] && [ ! -x "$(ODIN_CLANG_PATH)" ]; then \
		echo "error: Homebrew $(LLVM_HOMEBREW_FORMULA) Clang is missing; run ./tools/bootstrap-macos.sh" >&2; fail=1; \
	fi; \
	if [ ! -x "$(ODIN)" ] && ! command -v "$(ODIN)" >/dev/null 2>&1; then \
		echo "error: Odin is missing; run ./tools/bootstrap-macos.sh" >&2; fail=1; \
	else \
		actual="$$("$(ODIN)" version 2>/dev/null || true)"; \
		compiler_id="$${actual##* }"; \
		if [ "$$compiler_id" != "$(ODIN_VERSION_OUTPUT)" ]; then \
			echo "error: expected Odin $(ODIN_VERSION) ($(ODIN_VERSION_OUTPUT)), got: $$actual" >&2; fail=1; \
		fi; \
	fi; \
	if [ -z "$(SLANGC)" ] || [ ! -x "$(SLANGC)" ]; then \
		echo "error: Slang $(SLANG_VERSION) is missing; run ./tools/bootstrap-macos.sh" >&2; fail=1; \
	else \
		actual_slang="$$("$(SLANGC)" -version 2>&1 || true)"; \
		if [ "$$actual_slang" != "$(SLANG_VERSION_OUTPUT)" ]; then \
			echo "error: expected Slang $(SLANG_VERSION), got: $$actual_slang" >&2; fail=1; \
		fi; \
	fi; \
	if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists harfbuzz freetype2; then \
		echo "error: HarfBuzz and FreeType development packages are required" >&2; fail=1; \
	fi; \
	if [ ! -d "$(ZELDA_ENGINE_PACKAGES)" ]; then \
		echo "error: Zelda Engine packages not found at $(ZELDA_ENGINE_PACKAGES)" >&2; fail=1; \
	else \
		engine_commit="$$(git -C "$(ZELDA_ENGINE_ROOT)" rev-parse --short HEAD 2>/dev/null || echo unversioned)"; \
		echo "Zelda Engine: $$engine_commit ($(ZELDA_ENGINE_PACKAGES))"; \
	fi; \
	case "$$(uname -s)" in Darwin|Linux) ;; *) echo "error: unsupported build host: $$(uname -s)" >&2; fail=1;; esac; \
	mkdir -p "$(BUILD_DIR)" && test -w "$(BUILD_DIR)" || { echo "error: $(BUILD_DIR) is not writable" >&2; fail=1; }; \
	if [ "$$fail" -ne 0 ]; then echo "Run ./tools/bootstrap-macos.sh on macOS, then retry make doctor." >&2; exit 1; fi; \
	echo "Toolchain OK: $(ODIN_VERSION), Slang $(SLANG_VERSION)"

build: doctor $(LEGACY_DEV_APP)

release: doctor $(RELEASE_APP)

profile-build: doctor $(LEGACY_PROFILE_APP)

instrumented-build: profile-build

$(LEGACY_DEV_APP): $(DEV_APP)
	@mkdir -p $(@D)
	ln -sfn dev/$(APP) $@

$(LEGACY_PROFILE_APP): $(PROFILE_APP)
	@mkdir -p $(@D)
	ln -sfn profile/$(APP) $@

run: build
	@echo "Build complete; launching $(DEV_APP)..."
	$(DEV_APP)

demo: build
	@echo "Build complete; launching deterministic demo..."
	$(DEV_APP) --demo

passage: build
	@echo "Build complete; launching Passage..."
	$(DEV_APP) --passage

agent: build
	@echo "Build complete; launching agent protocol..."
	$(DEV_APP) --agent

bot: build
	@echo "Build complete; launching strategist simulation..."
	$(DEV_APP) --simulate 100 strategist

simulate: build
	@echo "Build complete; launching comparison simulation..."
	$(DEV_APP) --simulate 100 all

$(DEV_APP): $(BUILD_INPUTS) $(DEV_DIR)/libgfx_signposts.a $(addprefix $(DEV_DIR)/shaders/,$(SHADER_NAMES)) $(addprefix $(DEV_DIR)/,$(ASSET_PATHS))
	@mkdir -p $(@D)
	$(ODIN) build src $(COMMON_ODIN_FLAGS) -out:$@ $(DEV_ODIN_FLAGS) -extra-linker-flags:"$(call link_flags,$(DEV_DIR))"

$(RELEASE_APP): $(BUILD_INPUTS) $(RELEASE_DIR)/libgfx_signposts.a $(addprefix $(RELEASE_DIR)/shaders/,$(SHADER_NAMES)) $(addprefix $(RELEASE_DIR)/,$(ASSET_PATHS))
	@mkdir -p $(@D)
	$(ODIN) build src $(COMMON_ODIN_FLAGS) -out:$@ $(RELEASE_ODIN_FLAGS) -extra-linker-flags:"$(call link_flags,$(RELEASE_DIR))"

$(PROFILE_APP): $(BUILD_INPUTS) $(PROFILE_DIR)/libgfx_signposts.a $(addprefix $(PROFILE_DIR)/shaders/,$(SHADER_NAMES)) $(addprefix $(PROFILE_DIR)/,$(ASSET_PATHS))
	@mkdir -p $(@D)/timings
	$(ODIN) build src $(COMMON_ODIN_FLAGS) -out:$@ $(PROFILE_ODIN_FLAGS) -show-more-timings \
		-export-timings:json -export-timings-file:$(PROFILE_DIR)/timings/compiler.json \
		-extra-linker-flags:"$(call link_flags,$(PROFILE_DIR))"
ifeq ($(shell uname -s),Darwin)
	dsymutil $@ -o $@.dSYM
endif

define native_library
$(1)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $$(@D)
	$(CC) -O2 -c $$< -o $(1)/gfx_signposts.o
	$(AR) rcs $$@ $(1)/gfx_signposts.o
endef
$(eval $(call native_library,$(DEV_DIR)))
$(eval $(call native_library,$(RELEASE_DIR)))
$(eval $(call native_library,$(PROFILE_DIR)))
$(eval $(call native_library,$(TEST_DIR)))

define profile_shaders
$(1)/shaders/%.spv: $(GENERATED_DIR)/shaders/%.spv
	@mkdir -p $$(@D)
	cp $$< $$@
endef
$(eval $(call profile_shaders,$(DEV_DIR)))
$(eval $(call profile_shaders,$(RELEASE_DIR)))
$(eval $(call profile_shaders,$(PROFILE_DIR)))

define copy_asset
$(1)/$(2): $(3)
	@mkdir -p $$(@D)
	cp $$< $$@
endef

define profile_assets
$(eval $(call copy_asset,$(1),assets/fonts/Iosevka-Regular.ttf,assets/fonts/Iosevka-Regular.ttf))
$(eval $(call copy_asset,$(1),assets/fonts/NotoSansSymbols2-Regular.ttf,assets/fonts/NotoSansSymbols2-Regular.ttf))
$(eval $(call copy_asset,$(1),assets/fonts/ZeldaSans-Regular-v1.otf,assets/fonts/Iosevka-Regular.ttf))
$(eval $(call copy_asset,$(1),assets/fonts/ZeldaSerif-Regular-v0_1.otf,assets/fonts/ZeldaSerif-Regular-v0_1.otf))
$(eval $(call copy_asset,$(1),assets/icons/ui-icon-atlas-garden.png,assets/icons/ui-icon-atlas-garden.png))
$(eval $(call copy_asset,$(1),assets/icons/depth-planes-strip.png,assets/icons/depth-planes/depth-planes-strip.png))
$(eval $(call copy_asset,$(1),assets/ships/ship-components-engraved.png,assets/ships/ship-components-engraved.png))
$(eval $(call copy_asset,$(1),assets/ships/ship-components-map.png,assets/ships/ship-components-map.png))
$(eval $(call copy_asset,$(1),assets/ships/ship-damage-atlas.png,assets/ships/ship-damage-atlas.png))
$(eval $(call copy_asset,$(1),assets/ships/ship-engine-effects-atlas.png,assets/ships/ship-engine-effects-atlas.png))
$(eval $(call copy_asset,$(1),assets/ships/ship-markings-atlas.png,assets/ships/ship-markings-atlas.png))
$(eval $(call copy_asset,$(1),assets/ships/combat-archetype-icons-atlas-v1.png,assets/ships/combat-archetype-icons-atlas-v1.png))
endef
$(eval $(call profile_assets,$(DEV_DIR)))
$(eval $(call profile_assets,$(RELEASE_DIR)))
$(eval $(call profile_assets,$(PROFILE_DIR)))

define compile_shader
$(GENERATED_DIR)/shaders/$(1): $(2) toolchain.mk
	@mkdir -p $$(@D)
	@test -n "$(SLANGC)" && test -x "$(SLANGC)" || { echo "error: Slang is required; run make bootstrap" >&2; exit 1; }
	$(SLANGC) $$< -entry $(3) -stage $(4) -target spirv -profile spirv_1_5 -o $$@
endef
$(eval $(call compile_shader,ui.vert.spv,$(UI_SHADER),vertex_main,vertex))
$(eval $(call compile_shader,ui.frag.spv,$(UI_SHADER),fragment_main,fragment))
$(eval $(call compile_shader,ui-post.vert.spv,$(UI_SHADER),post_vertex,vertex))
$(eval $(call compile_shader,ui-post.frag.spv,$(UI_SHADER),post_fragment,fragment))
$(eval $(call compile_shader,close_engagement_3d.vert.spv,$(COMBAT_3D_SHADER),line_vertex,vertex))
$(eval $(call compile_shader,close_engagement_3d.frag.spv,$(COMBAT_3D_SHADER),fragment_main,fragment))
$(eval $(call compile_shader,close_engagement_contact.vert.spv,$(COMBAT_3D_SHADER),contact_vertex,vertex))
$(eval $(call compile_shader,close_engagement_terrain.vert.spv,$(COMBAT_3D_SHADER),terrain_vertex,vertex))
$(eval $(call compile_shader,close_engagement_terrain.frag.spv,$(COMBAT_3D_SHADER),terrain_fragment,fragment))
$(eval $(call compile_shader,close_engagement_background.vert.spv,$(COMBAT_3D_SHADER),background_vertex,vertex))
$(eval $(call compile_shader,close_engagement_background.frag.spv,$(COMBAT_3D_SHADER),background_fragment,fragment))
$(eval $(call compile_shader,close_engagement_nebula.vert.spv,$(COMBAT_NEBULA_SHADER),nebula_vertex,vertex))
$(eval $(call compile_shader,close_engagement_nebula.frag.spv,$(COMBAT_NEBULA_SHADER),nebula_fragment,fragment))
$(eval $(call compile_shader,close_engagement_debris.vert.spv,$(COMBAT_DEBRIS_SHADER),debris_vertex,vertex))
$(eval $(call compile_shader,close_engagement_debris.frag.spv,$(COMBAT_DEBRIS_SHADER),debris_fragment,fragment))

check-module-size:
	@find src packages -type f -name '*.odin' -exec wc -l {} + | awk '\
		$$2 != "total" && $$1 > $(MODULE_SIZE_TARGET) {printf "warning: %s has %d lines (target: $(MODULE_SIZE_TARGET))\n", $$2, $$1} \
		$$2 != "total" && $$1 > $(MODULE_SIZE_HARD_LIMIT) {failed = 1} \
		END {if (failed) {print "error: Odin source file exceeds the $(MODULE_SIZE_HARD_LIMIT)-line hard limit"; exit 1}}'

fmt:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required; run make bootstrap" >&2; exit 1; }
	find src packages tools -type f -name '*.odin' -exec $(ODINFMT) -w {} +

check: doctor check-module-size $(TEST_DIR)/libgfx_signposts.a
	@! rg -n '^(Passage_Node|Passage_Site_Record|Node_Family|Objective_Kind|Approach|MAX_PASSAGE_NODES)[[:space:]]*::' packages/game src --glob '*.odin'
	@! rg -n '\b(Passage_Node|Passage_Site_Record|Node_Family|Objective_Kind|MAX_PASSAGE_NODES|Node_Revealed|Node_Resolved)\b' packages/game src --glob '*.odin'
	$(ODIN) check src $(COMMON_ODIN_FLAGS)
	$(ODIN) check packages/game $(COMMON_ODIN_FLAGS) -no-entry-point

test: test-all

test-all: doctor $(TEST_DIR)/libgfx_signposts.a
	@status=0; \
	$(ODIN) test tests/game -all-packages $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) || status=1; \
	$(ODIN) test $(ZELDA_ENGINE_PACKAGES)/canvas2d $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -out:$(TEST_DIR)/canvas-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))" || status=1; \
	$(ODIN) test src $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -out:$(TEST_DIR)/src-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))" || status=1; \
	exit $$status

test-game: doctor
	$(ODIN) test tests/game -all-packages $(COMMON_ODIN_FLAGS) $(TEST_FLAGS)

test-canvas: doctor $(TEST_DIR)/libgfx_signposts.a
	$(ODIN) test $(ZELDA_ENGINE_PACKAGES)/canvas2d $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -out:$(TEST_DIR)/canvas-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))"

test-src: doctor $(TEST_DIR)/libgfx_signposts.a
	$(ODIN) test src $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -out:$(TEST_DIR)/src-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))"

test-fast: doctor $(TEST_DIR)/libgfx_signposts.a
	$(ODIN) test tests/game -all-packages $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -define:ODIN_TEST_NAMES="$$(sh tools/test-names.sh $(GAME_FAST_TEST_FILES))"
	$(ODIN) test $(ZELDA_ENGINE_PACKAGES)/canvas2d $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -out:$(TEST_DIR)/canvas-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))"
	$(ODIN) test src $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -define:ODIN_TEST_NAMES="$$(sh tools/test-names.sh $(SRC_FAST_TEST_FILES))" -out:$(TEST_DIR)/src-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))"

test-balance: doctor
	$(ODIN) test tests/game -all-packages $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -define:ODIN_TEST_NAMES="$$(sh tools/test-names.sh $(GAME_BALANCE_TEST_FILES))"

test-generative: doctor $(TEST_DIR)/libgfx_signposts.a
	$(ODIN) test tests/game -all-packages $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -define:ODIN_TEST_NAMES="$$(sh tools/test-names.sh $(GAME_GENERATIVE_TEST_FILES))"
	$(ODIN) test src $(COMMON_ODIN_FLAGS) $(TEST_FLAGS) -define:ODIN_TEST_NAMES="$$(sh tools/test-names.sh $(SRC_GENERATIVE_TEST_FILES))" -out:$(TEST_DIR)/src-tests -extra-linker-flags:"$(call link_flags,$(TEST_DIR))"

validate-balance: release
	$(RELEASE_APP) --sample-balance $(BALANCE_RUNS) $(BALANCE_SEED)

combat-ai-overnight: release
	mkdir -p $(dir $(COMBAT_AI_CHECKPOINT))
	$(RELEASE_APP) --combat-ai-overnight $(COMBAT_AI_CHECKPOINT) $(COMBAT_AI_HOURS) $(COMBAT_AI_RUNS) $(COMBAT_AI_SEED) $(COMBAT_AI_WORKERS)
	$(RELEASE_APP) --combat-ai-trials $(COMBAT_AI_CHECKPOINT) $(COMBAT_AI_REPORT) $(COMBAT_AI_TRIAL_RUNS) $(COMBAT_AI_TRIAL_BLOCKS) $(COMBAT_AI_TRIAL_SEED) $(COMBAT_AI_WORKERS)

combat-ai-trials: release
	mkdir -p $(dir $(COMBAT_AI_REPORT))
	$(RELEASE_APP) --combat-ai-trials $(COMBAT_AI_CHECKPOINT) $(COMBAT_AI_REPORT) $(COMBAT_AI_TRIAL_RUNS) $(COMBAT_AI_TRIAL_BLOCKS) $(COMBAT_AI_TRIAL_SEED) $(COMBAT_AI_WORKERS)

package:
	@case "$$(uname -s)" in \
		Darwin) $(MAKE) package-macos ;; \
		Linux) $(MAKE) package-linux ;; \
		*) echo "Unsupported packaging host: $$(uname -s)"; exit 1 ;; \
	esac

package-macos: release
	@set -eu; \
	stage="$$(mktemp -d "$(abspath $(DIST_DIR)).stage.XXXXXX")"; \
	trap 'rm -rf "$$stage"' EXIT HUP INT TERM; \
	app="$$stage/Last Best Hope.app"; \
	mkdir -p "$$app/Contents/MacOS" "$$app/Contents/Resources"; \
	cp "$(RELEASE_APP)" "$$app/Contents/MacOS/$(APP)"; \
	cp -R "$(RELEASE_DIR)/shaders" "$$app/Contents/MacOS/shaders"; \
	cp -R "$(RELEASE_DIR)/assets" "$$app/Contents/MacOS/assets"; \
	cp packaging/macos/Info.plist "$$app/Contents/Info.plist"; \
	cp assets/icons/last-best-hope.icns "$$app/Contents/Resources/last-best-hope.icns"; \
	test -x "$$app/Contents/MacOS/$(APP)" && test -d "$$app/Contents/MacOS/shaders" && test -d "$$app/Contents/MacOS/assets"; \
	mkdir -p "$(DIST_DIR)"; \
	rm -rf "$(DIST_DIR)/Last Best Hope.app"; \
	mv "$$app" "$(DIST_DIR)/Last Best Hope.app"; \
	rm -rf "$$stage"; trap - EXIT HUP INT TERM

package-linux: release
	@set -eu; \
	stage="$$(mktemp -d "$(abspath $(DIST_DIR)).stage.XXXXXX")"; \
	trap 'rm -rf "$$stage"' EXIT HUP INT TERM; \
	root="$$stage/$(APP)-linux"; \
	mkdir -p "$$root/assets"; \
	cp "$(RELEASE_APP)" "$$root/$(APP)"; \
	cp -R "$(RELEASE_DIR)/shaders" "$$root/shaders"; \
	cp -R "$(RELEASE_DIR)/assets/." "$$root/assets/"; \
	cp assets/icons/last-best-hope.png "$$root/assets/$(APP).png"; \
	test -x "$$root/$(APP)" && test -d "$$root/shaders" && test -d "$$root/assets"; \
	mkdir -p "$(DIST_DIR)"; \
	tar -C "$$stage" -czf "$(DIST_DIR)/$(APP)-linux.tar.gz.tmp" "$(APP)-linux"; \
	mv "$(DIST_DIR)/$(APP)-linux.tar.gz.tmp" "$(DIST_DIR)/$(APP)-linux.tar.gz"; \
	rm -rf "$$stage"; trap - EXIT HUP INT TERM

clean:
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"

clean-tools:
	rm -rf "$(TOOLS_DIR)"
