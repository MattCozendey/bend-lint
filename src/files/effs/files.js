// Files
// =====
// The JS twins of files.c.

function files_list(path) {
  if (path.includes("\0")) return io_fail(22);
  try {
    return io_done(
      require("fs")
        .readdirSync(path)
        .map((name) => name + "\0")
        .join(""),
    );
  } catch (e) {
    return io_fail(io_code(e));
  }
}

function files_kind(path) {
  if (path.includes("\0")) return 0;
  try {
    const st = require("fs").statSync(path);
    return st.isFile() ? 1 : st.isDirectory() ? 2 : 3;
  } catch {
    return 0;
  }
}

function files_real(path) {
  if (path.includes("\0")) return io_fail(22);
  try {
    return io_done(require("fs").realpathSync.native(path).replaceAll("\\", "/"));
  } catch (e) {
    return io_fail(io_code(e));
  }
}

io_eff(CID(list.raw), files_list);
io_eff(CID(kind), files_kind);
io_eff(CID(real), files_real);
