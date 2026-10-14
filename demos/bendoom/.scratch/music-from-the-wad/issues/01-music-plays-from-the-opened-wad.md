# Render audio from the opened WAD

**Status:** needs-triage

Music and sound effects are rendered at package build time. Overriding
`BENDOOM_IWAD` at runtime changes the level and graphics but leaves that audio
unchanged. One WAD per package is sufficient for the current E1M1 scope.
Revisit this when supporting additional maps or runtime WAD selection.

- [ ] Render each map's music and effects from the opened WAD, including its `GENMIDI`.
- [ ] Keep zero differing samples against Chocolate Doom in `tools/listen.nu`.
- [ ] Sustain 35 frames per second without audio underruns, or measure the
      startup delay if rendering at load time.
- [ ] Remove the build-time audio renderers, packaged raw files and
      `BENDOOM_MUSIC` / `BENDOOM_SOUNDS` once their runtime replacement works.
