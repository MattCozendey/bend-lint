BEND ?= bend
UI_BEND ?= $(BEND)
RUN_ARGS ?= --gpu off
CUDA_HOME ?= $(if $(wildcard /opt/cuda),/opt/cuda,$(if $(wildcard /usr/local/cuda),/usr/local/cuda,))
export CUDA_HOME

BINARY := build/bend-voxel-rewrite
SOURCES := atelier.bend atelier_assets.bend scene_data.bend main.bend voxel.bend render.bend material.bend lighting.bend dump.bend
UI_TEST_SOURCES := deps/bend-ui-test/uitest.bend deps/bend-ui-test/plan.bend deps/bend-ui-test/uitest.c deps/bend-ui-test/uitest.js

.PHONY: all run proof test geometry materials lighting brush-ui images ui flight-ui benchmark atelier dda clean

all: $(BINARY)

build:
	mkdir -p build

$(BINARY): $(SOURCES) | build
	$(BEND) main.bend -o $@

build/atelier-check: scripts/atelier_evidence.bend $(SOURCES) | build
	$(BEND) scripts/atelier_evidence.bend -o $@

atelier: build/atelier-check
	./build/atelier-check --gpu off --threads 1

build/geometry-dump: scripts/geometry_dump.bend voxel.bend material.bend | build
	$(BEND) scripts/geometry_dump.bend -o $@

build/reference-check: scripts/reference_check.bend | build
	$(BEND) scripts/reference_check.bend -o $@

build/image-checker: scripts/image_check.bend scripts/image_data.bend scripts/sha256.bend | build
	$(BEND) scripts/image_check.bend -o $@

build/benchmark: scripts/benchmark.bend scripts/benchmark_host.bend scripts/benchmark_number.bend scripts/sha256.bend | build
	$(BEND) scripts/benchmark.bend -o $@

build/frame-profile: scripts/frame_profile.bend $(SOURCES) | build
	$(BEND) scripts/frame_profile.bend -o $@

build/dda-compare: scripts/dda_compare.bend dda.bend $(SOURCES) | build
	$(BEND) scripts/dda_compare.bend -o $@

build/dda-benchmark: scripts/dda_benchmark.bend scripts/dda_compare.bend dda.bend scripts/benchmark.bend scripts/benchmark_number.bend scripts/benchmark_host.bend scripts/sha256.bend $(SOURCES) | build
	$(BEND) scripts/dda_benchmark.bend -o $@

build/dda-profile: scripts/dda_profile.bend dump.bend | build
	$(BEND) scripts/dda_profile.bend -o $@

build/dda-estimate-profile: scripts/dda_estimate_profile.bend scripts/dda_profile.bend dump.bend | build
	$(BEND) scripts/dda_estimate_profile.bend -o $@

build/dda-ab: scripts/dda_ab.bend scripts/benchmark.bend scripts/benchmark_number.bend scripts/benchmark_host.bend scripts/sha256.bend | build
	$(BEND) scripts/dda_ab.bend -o $@

dda: build/dda-compare
	./build/dda-compare --gpu off --threads 1 -- --cube --verify

build/material-check: scripts/material_check.bend $(SOURCES) | build
	$(BEND) scripts/material_check.bend -o $@

build/lighting-check: scripts/lighting_check.bend $(SOURCES) | build
	$(BEND) scripts/lighting_check.bend -o $@

lighting: build/lighting-check
	mkdir -p build/lighting/cpu build/lighting/gpu
	./build/lighting-check --gpu off --threads 1 -- --output build/lighting/cpu
	./build/lighting-check --gpu on --threads 1 -- --output build/lighting/gpu
	for image in build/lighting/cpu/*.ppm; do cmp "$$image" "build/lighting/gpu/$${image##*/}" || exit $$?; done

materials: build/material-check
	mkdir -p build/materials/cpu build/materials/gpu
	./build/material-check --gpu off --threads 1 -- --output build/materials/cpu
	./build/material-check --gpu on --threads 1 -- --output build/materials/gpu
	for image in build/materials/cpu/*.ppm build/materials/cpu/swatches.txt; do cmp "$$image" "build/materials/gpu/$${image##*/}" || exit $$?; done

build/ui-check: scripts/ui_check.bend scripts/ui_capture.bend $(UI_TEST_SOURCES) $(SOURCES) .gitmodules | build
	$(UI_BEND) scripts/ui_check.bend -o $@

build/flight-ui-check: scripts/flight_ui_check.bend scripts/ui_check.bend scripts/ui_capture.bend $(UI_TEST_SOURCES) $(SOURCES) .gitmodules | build
	$(UI_BEND) scripts/flight_ui_check.bend -o $@

flight-ui: build/flight-ui-check
	./build/flight-ui-check --gpu on -- --output .audit/screenshots/flight-ui

build/brush-ui-check: scripts/brush_ui_check.bend scripts/flight_ui_check.bend scripts/ui_check.bend scripts/ui_capture.bend $(UI_TEST_SOURCES) $(SOURCES) .gitmodules | build
	$(UI_BEND) scripts/brush_ui_check.bend -o $@

brush-ui: build/brush-ui-check
	./build/brush-ui-check --gpu on -- --output .audit/screenshots/brush-ui

run: $(BINARY)
	./$(BINARY) $(RUN_ARGS)

proof:
	$(BEND) PROOF.bend
	$(BEND) PROOF.bend --verdict

geometry: build/geometry-dump build/reference-check
	./build/reference-check --gpu off

images: $(BINARY) build/image-checker
	./build/image-checker --gpu off

ui: build/ui-check
	./build/ui-check --gpu on -- --output .audit/screenshots/ui

benchmark: $(BINARY) build/benchmark
	./build/benchmark --gpu off

test: proof geometry materials lighting images

clean:
	rm -rf build
