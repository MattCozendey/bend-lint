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

// The answer of a call that changes the file system and gives nothing.
function files_done(call) {
  try {
    call();
    return io_done({ $: CID(Unit) });
  } catch (e) {
    return io_fail(io_code(e));
  }
}

function files_remove(path) {
  if (path.includes("\0")) return io_fail(22);
  const fs = require("fs");
  return files_done(() =>
    fs.statSync(path).isDirectory() ? fs.rmdirSync(path) : fs.unlinkSync(path),
  );
}

function files_make_folder(path) {
  if (path.includes("\0")) return io_fail(22);
  return files_done(() => require("fs").mkdirSync(path));
}

function files_enter(path) {
  if (path.includes("\0")) return io_fail(22);
  return files_done(() => process.chdir(path));
}

io_eff(CID(list.raw), files_list);
io_eff(CID(kind), files_kind);
io_eff(CID(real), files_real);
io_eff(CID(remove), files_remove);
io_eff(CID(make_folder), files_make_folder);
io_eff(CID(enter), files_enter);
