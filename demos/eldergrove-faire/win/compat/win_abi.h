// Included by win/build.sh right after park.c's attribute macros.
//
// The work loop's segments pass the runtime's Env (a 16-byte struct) and
// enter one another by musttail. The Windows x64 convention passes such a
// struct by reference to a copy, which a tail call cannot do, so here the
// segments (and the table that holds them) use the System V convention,
// which passes it in two registers. GCC switches conventions per function.
#undef PRESERVE
#define PRESERVE(A)              PRESERVE_##A
#define PRESERVE_preserve_none   __attribute__((sysv_abi))
#define PRESERVE_preserve_most
