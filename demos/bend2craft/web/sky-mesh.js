// Pure sky bodies: square sun and moon plus a deterministic star dome.
// Positions stay within the fog-free range so the shared textured shader
// renders them at full color. Testable without a browser.

import { brightness } from "./daynight.js";

export const SKY_RADIUS = 22;

export function starPosition(index, radius) {
  const a = (index * 2.399963) % (Math.PI * 2);
  const b = ((index * 0.754877) % 1) * Math.PI * 0.48 + 0.03;
  return [
    Math.cos(a) * Math.cos(b) * radius,
    Math.sin(b) * radius,
    Math.sin(a) * Math.cos(b) * radius,
  ];
}

// Appends axis-aligned boxes as [center, size, color] entries; the adapter
// turns them into quads. Returns the entry list for tests.
export function skyBodies(eye, time) {
  const bodies = [];
  const night = 1 - (brightness(time) - 0.32) / 0.68;
  if (night > 0.45) {
    const dim = Math.min(1, (night - 0.45) * 2.5);
    for (let i = 0; i < 130; i += 1) {
      const [sx, sy, sz] = starPosition(i, SKY_RADIUS);
      bodies.push({
        center: [eye[0] + sx, eye[1] + sy, eye[2] + sz],
        size: 0.12,
        color: [0.9 * dim, 0.93 * dim, dim],
      });
    }
  }
  const angle = time * Math.PI * 2;
  const sunHeight = Math.sin(angle);
  const sunDir = [Math.cos(angle), sunHeight, 0.25];
  const length = Math.hypot(sunDir[0], sunDir[1], sunDir[2]);
  const unit = sunDir.map((v) => v / length);
  if (sunHeight > -0.08) {
    bodies.push({
      center: [eye[0] + unit[0] * SKY_RADIUS, eye[1] + unit[1] * SKY_RADIUS, eye[2] + unit[2] * SKY_RADIUS],
      size: 2.2,
      color: [1, 0.85, 0.4],
    });
  } else {
    bodies.push({
      center: [eye[0] - unit[0] * SKY_RADIUS, eye[1] - unit[1] * SKY_RADIUS, eye[2] - unit[2] * SKY_RADIUS],
      size: 1.5,
      color: [0.85, 0.9, 1],
    });
  }
  return bodies;
}
