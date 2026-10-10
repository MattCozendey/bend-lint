// host
// ====
// The effects the host answers (see host.ts): each asks the host's main
// thread and waits; the answer comes as a main.bend value. There is no C
// twin: the host is JS.

function bendlint_get_check(path, declarations, bodies, facts) {
  return globalThis.BEND_HOST.ask({ op: "check", path, declarations, bodies, facts });
}

function bendlint_restart_with_rules(files) {
  const out = [];
  for (let xs = files; xs.$ === CID(Con); xs = xs.tail) {
    out.push(xs.head);
  }
  return globalThis.BEND_HOST.ask({ op: "restart", files: out });
}

function bendlint_get_keeps_declarations(path, text) {
  return globalThis.BEND_HOST.ask({ op: "same", path, text });
}

function bendlint_get_glob(pattern) {
  return globalThis.BEND_HOST.ask({ op: "glob", pattern });
}

io_eff(CID(get_check), bendlint_get_check);
io_eff(CID(get_glob), bendlint_get_glob);
io_eff(CID(get_keeps_declarations), bendlint_get_keeps_declarations);
io_eff(CID(restart_with_rules), bendlint_restart_with_rules);
