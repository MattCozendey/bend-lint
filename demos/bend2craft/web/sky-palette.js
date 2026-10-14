export const SUN_ANGULAR_SPEED = 0.08;

function clamp01(value) {
  return Math.max(0, Math.min(1, Number(value)));
}

function cssRgb(color) {
  return `rgb(${color.map((channel) => Math.round(channel * 255)).join(", ")})`;
}

export function sunDirection(time) {
  const phase = Number(time) * SUN_ANGULAR_SPEED;
  const direction = [-Math.cos(phase), Math.sin(phase), 0.28];
  const length = Math.hypot(...direction) || 1;
  return direction.map((channel) => channel / length);
}

export function skyPalette(daylight, time = 0) {
  const light = clamp01(daylight);
  const top = [
    0.025 + 0.34 * light,
    0.06 + 0.48 * light,
    0.13 + 0.72 * light,
  ];
  const horizon = [
    0.09 + 0.58 * light,
    0.12 + 0.65 * light,
    0.2 + 0.69 * light,
  ];
  const direction = sunDirection(time);
  const twilight = 1 - clamp01(Math.abs(direction[1]) / 0.35);
  const daylightColor = [1, 0.94, 0.76];
  const horizonColor = [1, 0.43, 0.2];
  const intensity = 0.25 + light * 0.75;
  const sunColor = daylightColor.map((channel, index) => (
    (channel + (horizonColor[index] - channel) * twilight) * intensity
  ));
  return {
    top,
    horizon,
    sunDirection: direction,
    sunColor,
    cssTop: cssRgb(top),
    cssHorizon: cssRgb(horizon),
  };
}
