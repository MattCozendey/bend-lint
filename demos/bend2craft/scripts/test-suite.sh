#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS=(
  tests/bend-list.test.mjs
  tests/world-bridge.test.mjs
  tests/bend-bridge.test.mjs
  tests/world-state-bend.test.mjs
  tests/multiplayer-bend.test.mjs
  tests/multiplayer-mobs-bend.test.mjs
  tests/multiplayer-room.test.mjs
  tests/multiplayer-transport.test.mjs
  tests/native-bridge.test.mjs
  tests/native-join.test.mjs
  tests/multiplayer-client.test.mjs
  tests/multiplayer-mob-world.test.mjs
  tests/multiplayer-server-world.test.mjs
  tests/multiplayer-moves.test.mjs
  tests/world-chunk-golden.test.mjs
  tests/world-coordinates.test.mjs
  tests/chunk-world.test.mjs
  tests/chunk-world-remote-edits.test.mjs
  tests/chunk-world-light-stencil.test.mjs
  tests/worker-scheduler.test.mjs
  tests/chunk-worker-core.test.mjs
  tests/structures-bend.test.mjs
  tests/village-path-bend.test.mjs
  tests/villagers-bend.test.mjs
  tests/horizon-bend.test.mjs
  tests/horizon-grid.test.mjs
  tests/horizon-lod-bend.test.mjs
  tests/lod-terrain.test.mjs
  tests/simulation-bend.test.mjs
  tests/world-simulation.test.mjs
  tests/fluids-bend.test.mjs
  tests/fire-bend.test.mjs
  tests/redstone-bend.test.mjs
  tests/redstone-grid-bend.test.mjs
  tests/redstone-clock-bend.test.mjs
  tests/redstone-machines-bend.test.mjs
  tests/redstone-observer-bend.test.mjs
  tests/redstone-all-bend.test.mjs
  tests/redstone-blocks.test.mjs
  tests/world-block-chunk.test.mjs
  tests/ore-distribution.test.mjs
  tests/inventory-bend-contract.test.mjs
  tests/redstone-adapter.test.mjs
  tests/simulation-ticker.test.mjs
  tests/crops-bend.test.mjs
  tests/farmland-bend.test.mjs
  tests/save-state.test.mjs
  tests/persistent-save.test.mjs
  tests/entity-save.test.mjs
  tests/entity-chunks.test.mjs
  tests/drop-ground-cache.test.mjs
  tests/async-mesh-cache.test.mjs
  tests/greedy-mesh.test.mjs
  tests/mesh-merge.test.mjs
  tests/terrain-edit-visibility.test.mjs
  tests/mesh-cache.test.mjs
  tests/mesh-rebuild-scheduler.test.mjs
  tests/villager-terrain.test.mjs
  tests/mesh-worker.test.mjs
  tests/terrain-vertex-builder.test.mjs
  tests/material-textures.test.mjs
  tests/visual-quality.test.mjs
  tests/graphics-effects.test.mjs
  tests/cloud-lighting.test.mjs
  tests/frame-pacer.test.mjs
  tests/gl-render-target.test.mjs
  tests/sun-shadow.test.mjs
  tests/sun-shadow-wiring.test.mjs
  tests/vertex-buffer-compose.test.mjs
  tests/chunk-frustum.test.mjs
  tests/webgpu-capabilities.test.mjs
  tests/webgpu-chunk-buffers.test.mjs
  tests/webgl-chunk-buffers.test.mjs
  tests/webgpu-chunk-updates.test.mjs
  tests/webgpu-frame-readback.test.mjs
  tests/webgpu-terrain-presentation.test.mjs
  tests/surface-materials.test.mjs
  tests/mob-models.test.mjs
  tests/visual-motion.test.mjs
  tests/frame-metrics.test.mjs
  tests/hud-visibility.test.mjs
  tests/mining-controller.test.mjs
  tests/mining-progress.test.mjs
  tests/entity-shadow.test.mjs
  tests/vfx.test.mjs
  tests/vfx-wiring.test.mjs
  tests/first-person-hand.test.mjs
  tests/material-lighting.test.mjs
  tests/sky-palette.test.mjs
  tests/texture-atlas.test.mjs
  tests/atlas-mipmap-safety.test.mjs
  tests/item-atlas.test.mjs
  tests/character-view.test.mjs
  tests/aim.test.mjs
  tests/daynight.test.mjs
  tests/mob-mesh.test.mjs
  tests/sfx.test.mjs
  tests/sky-mesh.test.mjs
  tests/light-bend.test.mjs
  tests/light-dirty-bend.test.mjs
  tests/light-flood-bend.test.mjs
  tests/light-flood-grid.test.mjs
  tests/inventory-bend.test.mjs
  tests/chest-bend.test.mjs
  tests/chests-bend.test.mjs
  tests/equipment-bend.test.mjs
  tests/experience-bend.test.mjs
  tests/interactions-bend.test.mjs
  tests/furnace-bend.test.mjs
  tests/furnaces-bend.test.mjs
  tests/player-bend.test.mjs
  tests/entities-bend.test.mjs
  tests/inventory.test.mjs
  tests/inventory-ux.test.mjs
  tests/game-state.test.mjs
  tests/camera.test.mjs
  tests/audio.test.mjs
  tests/pointer-lock.test.mjs
  tests/seed-input.test.mjs
  tests/seed-world.test.mjs
  tests/profiles.test.mjs
  tests/menu-navigation.test.mjs
  tests/modal-focus.test.mjs
  tests/settings.test.mjs
  tests/options-panel.test.mjs
  tests/backend-fallback.test.mjs
  tests/ui-shell.test.mjs
  tests/startup-contract.test.mjs
  tests/boot-resilience.test.mjs
)

# A newline-delimited set keeps this membership check working on the bash 3.2
# that ships with macOS, which has no associative arrays.
LISTED_TESTS=$'\n'
for test_file in "${TESTS[@]}"; do
  LISTED_TESTS+="$test_file"$'\n'
  if [[ ! -f "$ROOT/$test_file" ]]; then
    printf 'Listed test does not exist: %s\n' "$test_file" >&2
    exit 1
  fi
done

while IFS= read -r discovered; do
  [[ -z "$discovered" ]] && continue
  case "$LISTED_TESTS" in
    *$'\n'"$discovered"$'\n'*) ;;
    *)
      printf 'Test file is not registered in scripts/test-suite.sh: %s\n' "$discovered" >&2
      exit 1
      ;;
  esac
done < <(cd "$ROOT" && printf '%s\n' tests/*.test.mjs | sort)

printf 'Running %d tests\n' "${#TESTS[@]}"
for index in "${!TESTS[@]}"; do
  test_file="${TESTS[$index]}"
  printf '[%02d/%02d] %s\n' "$((index + 1))" "${#TESTS[@]}" "$test_file"
  bash "$ROOT/scripts/run-bun.sh" "$ROOT/$test_file"
done

# Native Bend probes write disposable save files relative to their working
# directory. Run them away from the real local save without changing imports.
BEND_TESTS=(
  tests/native-world.bend
  tests/native-input.bend
  lab/native/render-probe/render_probe_test.bend
  lab/native/save-probe/snapshot_test.bend
  lab/native/bench-probe/bench_probe_test.bend
  lab/native/protocol-probe/protocol_test.bend
  native/player_test.bend
  native/voxel_test.bend
  lab/native/tcp-probe/transport_test.bend
  native/save_test.bend
  native/face_test.bend
  native/paint_test.bend
  native/face_extraction_test.bend
  native/frame_test.bend
  native/pointer_test.bend
  native/bag_test.bend
  native/hud_test.bend
  native/debug_test.bend
  native/debug_toggle_test.bend
  native/texture_test.bend
  native/net_test.bend
  native/body_test.bend
  native/tag_test.bend
  native/screen_test.bend
  native/stores_test.bend
  native/stash_test.bend
  native/shade_test.bend
  native/sky_test.bend
  native/scenery_test.bend
  native/size_test.bend
  native/digging_test.bend
  native/hour_test.bend
  native/play_test.bend
  native/room_test.bend
)
mkdir -p "$ROOT/scratchpad"
native_test_dir="$(mktemp -d "$ROOT/scratchpad/native-tests.XXXXXX")"
trap 'rm -rf "$native_test_dir"' EXIT
mkdir "$native_test_dir/native"
for test_file in "${BEND_TESTS[@]}"; do
  printf '[bend] %s\n' "$test_file"
  (cd "$native_test_dir" && BEND_NO_TELEMETRY=1 bash "$ROOT/scripts/check-bend.sh" "$test_file")
done
printf 'All %d JavaScript tests and %d native Bend probes passed.\n' "${#TESTS[@]}" "${#BEND_TESTS[@]}"
