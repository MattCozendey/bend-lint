// Pointer
// =======

// The JS lane has no window of its own to hold a cursor in, so it never
// reads the host's pointer.
function pointer_open(title) {
  return 0;
}

io_eff(CID(host_open), pointer_open);
