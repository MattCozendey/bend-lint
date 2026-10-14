# Document C effect header requirements

**Status:** needs-info

In Bend e6676b0, `bend2/comp.ts` included `<sys/stat.h>` only for CUDA builds.
A custom effect using `fstat` without its own include therefore compiled with
CUDA but failed on CPU builds. Bendoom no longer ships custom C effects.

Check the current compiler before reporting. Ask the effect documentation to
state that effects must include their own required headers.
