// host
// ====
// The effects the host answers (see host.ts): each asks the host's main
// thread and waits; the answer comes as a main.bend value. There is no C
// twin: the host is JS.

function bendlint_get_check_failure(path) {
  return globalThis.BEND_HOST.ask({ op: "check", path });
}

io_eff(CID(get_check_failure), bendlint_get_check_failure);
