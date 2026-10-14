import assert from "node:assert/strict";
import { cameraFov } from "../web/camera.js";

assert.equal(cameraFov(75), 75);
assert.equal(cameraFov(75, { sprinting: true }), 79);
assert.equal(cameraFov(75, { damage: 20 }), 78);
assert.equal(cameraFov(75, { underwater: true }), 70);
assert.equal(cameraFov(75, { sprinting: true, damage: 20, underwater: true }), 77);
assert.equal(cameraFov(200), 130);
assert.throws(() => cameraFov("wide"), TypeError);
console.log("camera fov ok");
