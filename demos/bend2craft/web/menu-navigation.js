export function continueTarget(doc) {
  const profile = doc?.profiles?.find((entry) => entry.id === doc.activeProfileId);
  if (profile === undefined || !Array.isArray(profile.worlds) || profile.worlds.length === 0) return null;
  const world = [...profile.worlds].sort((left, right) => {
    const played = Number(right.lastPlayed ?? 0) - Number(left.lastPlayed ?? 0);
    return played !== 0 ? played : String(left.id).localeCompare(String(right.id));
  })[0];
  return world === undefined ? null : { profileId: profile.id, worldId: world.id };
}
