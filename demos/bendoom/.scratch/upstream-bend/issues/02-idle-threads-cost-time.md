# Investigate idle worker overhead

**Status:** needs-info

The game currently has no parallel work, and its launcher uses `--threads 1`.
Earlier measurements on Bend e6676b0 found extra workers slowed the window loop.
The suspected cause is worker wakeups and synchronization in `pool_turn` and
`pool_work` in `bend2/comp.ts`; this has not been isolated.

Before reporting upstream or adding parallel game work, compare the window
benchmark with 1, 2 and 12 threads on the current compiler and profile the
multi-threaded run. Check the headless renderer separately to isolate window
and runtime overhead.
