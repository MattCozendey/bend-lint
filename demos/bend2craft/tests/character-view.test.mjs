import assert from "node:assert/strict";
import {
  characterRenderDescriptor,
  heldItemPose,
} from "../web/character-view.js";

const empty = heldItemPose({ block: 0, count: 0 });
assert.equal(empty.visible, false);
assert.equal(empty.item, null);
assert.equal(empty.category, "empty");
assert.equal(empty.model, "none");
assert.equal(empty.pose, null);
assert.equal(empty.count, 0);

const emptyCharacter = characterRenderDescriptor(null);
assert.equal(emptyCharacter.kind, "person");
assert.equal(emptyCharacter.heldItem.visible, false);
assert.equal(emptyCharacter.heldItem.category, "empty");
assert.deepEqual(emptyCharacter.parts.map((part) => part.name), [
  "head",
  "torso",
  "left_arm",
  "right_arm",
  "left_leg",
  "right_leg",
]);

for (const [block, item] of [[1, "stone"], [5, "wood"], [7, "water"], [11, "furnace"], [22, "cobblestone"], [23, "obsidian"]]) {
  const descriptor = heldItemPose({ block, count: 32 });
  assert.equal(descriptor.visible, true);
  assert.equal(descriptor.item, item);
  assert.equal(descriptor.category, "block");
  assert.equal(descriptor.model, "cube");
  assert.equal(descriptor.block, block);
  assert.equal(descriptor.count, 32);
  assert.ok(Array.isArray(descriptor.pose.position));
  assert.ok(Array.isArray(descriptor.pose.rotation));
  assert.ok(Array.isArray(descriptor.pose.scale));
}

for (const item of ["wooden_pickaxe", "stone_pickaxe", "iron_pickaxe", "diamond_pickaxe", "wooden_hoe"]) {
  const descriptor = heldItemPose({ item, count: 1 });
  assert.equal(descriptor.visible, true);
  assert.equal(descriptor.item, item);
  assert.equal(descriptor.category, "tool");
  assert.equal(descriptor.model, item === "wooden_hoe" ? "hoe" : "pickaxe");
  assert.ok(descriptor.color.startsWith("#"));
}

const torch = heldItemPose({ block: 12, count: 1 });
assert.equal(torch.item, "torch");
assert.equal(torch.category, "torch");
assert.equal(torch.model, "torch");
assert.notDeepEqual(torch.pose, heldItemPose({ block: 1, count: 1 }).pose);

const bed = heldItemPose({ item: "bed", count: 1 });
assert.equal(bed.category, "bed");
assert.equal(bed.model, "bed");
assert.ok(bed.dimensions[0] > bed.dimensions[1]);

const door = heldItemPose({ item: "door", count: 1 });
assert.equal(door.category, "door");
assert.equal(door.model, "door");
assert.equal(door.block, 14);

const thirdPerson = characterRenderDescriptor({ item: "door", count: 1 });
assert.equal(thirdPerson.heldItem.item, "door");
assert.equal(thirdPerson.heldItem.category, "door");
assert.equal(thirdPerson.heldItem.model, "door");
assert.equal(thirdPerson.heldItem.pose.reference, "character");
assert.equal(thirdPerson.heldItem.pose.side, "right");
assert.notDeepEqual(thirdPerson.heldItem.pose, door.pose);

for (const selection of [
  { block: 1, count: 1 },
  { item: "stone_pickaxe", count: 1 },
  { item: "torch", count: 1 },
  { item: "bed", count: 1 },
  { item: "door", count: 1 },
]) {
  const descriptor = characterRenderDescriptor(selection);
  assert.equal(descriptor.heldItem.visible, true);
  assert.equal(descriptor.heldItem.pose.reference, "character");
  assert.equal(descriptor.heldItem.pose.side, "right");
}

const deterministicInput = { item: "diamond_pickaxe", count: 1, durability: 42 };
const heldA = heldItemPose(deterministicInput);
const heldB = heldItemPose(deterministicInput);
assert.deepEqual(heldA, heldB);
assert.equal(JSON.stringify(heldA), JSON.stringify(heldB));
assert.deepEqual(
  characterRenderDescriptor(deterministicInput),
  characterRenderDescriptor(deterministicInput),
);
assert.deepEqual(heldItemPose({ block: 12, count: 1 }), heldItemPose({ item: "torch", count: 1 }));

const genericItem = heldItemPose({ item: "diamond", count: 1 });
assert.equal(genericItem.category, "item");
assert.equal(genericItem.model, "item");

for (const item of ["wheat_seeds", "wheat"]) {
  const descriptor = heldItemPose({ item, count: 2 });
  assert.equal(descriptor.visible, true);
  assert.equal(descriptor.item, item);
  assert.equal(descriptor.category, "item");
  assert.ok(descriptor.pose);
}

console.log("character view ok");
