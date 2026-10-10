// get_real_path
// =============
// On POSIX, Bun's realpath reads a backslash as a separator, but it is a
// plain character there. So POSIX walks the path itself, with lstat and
// readlink, which read it as the OS does.

function bendlint_get_real_path_posix(path) {
  const fs = require("fs");
  const start = path.startsWith("/") ? path : process.cwd() + "/" + path;
  let todo = start.split("/");
  let done = [];
  let hops = 0;
  while (todo.length > 0) {
    const part = todo.shift();
    if (part === "" || part === ".") {
      continue;
    }
    if (part === "..") {
      done.pop();
      continue;
    }
    const at = "/" + done.concat([part]).join("/");
    if (!fs.lstatSync(at).isSymbolicLink()) {
      done.push(part);
      continue;
    }
    hops += 1;
    if (hops > 40) {
      throw Object.assign(new Error("too many links"), { code: "ELOOP" });
    }
    const target = fs.readlinkSync(at);
    todo = target.split("/").concat(todo);
    if (target.startsWith("/")) {
      done = [];
    }
  }
  return "/" + done.join("/");
}

function bendlint_get_real_path(path) {
  try {
    return io_done(
      process.platform === "win32"
        ? require("fs").realpathSync.native(path)
        : bendlint_get_real_path_posix(path),
    );
  } catch (e) {
    return io_fail(io_code(e));
  }
}

io_eff(CID(get_real_path), bendlint_get_real_path);
