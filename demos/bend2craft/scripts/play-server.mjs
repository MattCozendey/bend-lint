import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { attachNativeBridge } from "../server/native-bridge.mjs";
import { attachMultiplayer, lanAddresses } from "../server/node-host.mjs";

// Static file server for the built Bend2Craft bundle in dist/.
// English-only copy per repository rules. Dependency-free (Node stdlib).

const root = path.resolve(fileURLToPath(new URL("../dist/", import.meta.url)));
const port = Number(process.env.PORT ?? 8080);
// --lan listens on every interface so friends on the same network can join.
const lan = process.argv.includes("--lan");
const host = process.env.HOST ?? (lan ? "0.0.0.0" : "127.0.0.1");
// The native client joins the same room through a plain TCP port (server/native-bridge.mjs).
// NATIVE_PORT=0 closes that door.
const nativePort = Number(process.env.NATIVE_PORT ?? port + 1);
const shouldOpenBrowser = process.argv.includes("--open");
const repositoryRoot = path.resolve(root, "..");
// The shared multiplayer world lives outside dist/ so rebuilding keeps it.
const multiplayerFile = path.resolve(
  repositoryRoot,
  process.env.MULTIPLAYER_WORLD ?? path.join("worlds", "multiplayer.json"),
);
const multiplayerSeedText = process.env.SEED ?? "1337";
if (!/^\d+$/.test(multiplayerSeedText)) {
  throw new Error(`SEED must be a non-negative integer; received ${multiplayerSeedText}`);
}

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error(`PORT must be an integer from 1 to 65535; received ${process.env.PORT}`);
}
if (!Number.isInteger(nativePort) || nativePort < 0 || nativePort > 65535) {
  throw new Error(`NATIVE_PORT must be an integer from 0 to 65535; received ${process.env.NATIVE_PORT}`);
}
if (!existsSync(path.join(root, "index.html"))) {
  throw new Error(`Built bundle not found at ${root}. Run "npm run build" first.`);
}
const authorityModule = path.join(root, "multiplayer-authority.js");
if (!existsSync(authorityModule)) {
  throw new Error(`Multiplayer authority not found at ${authorityModule}. Run "npm run build" first.`);
}
const { default: authority, createServerWorld } = await import(pathToFileURL(authorityModule).href);

const types = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".mjs", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".wasm", "application/wasm"],
  [".png", "image/png"],
  [".jpg", "image/jpeg"],
  [".jpeg", "image/jpeg"],
  [".webp", "image/webp"],
  [".svg", "image/svg+xml"],
  [".ico", "image/x-icon"],
  [".txt", "text/plain; charset=utf-8"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

function noStore(response, status, body, type = "text/plain; charset=utf-8") {
  response.writeHead(status, {
    "cache-control": "no-store, max-age=0",
    "content-type": type,
    "x-content-type-options": "nosniff",
  });
  response.end(body);
}

function openBrowser(url) {
  let command;
  let args;
  if (process.platform === "win32") {
    command = "rundll32.exe";
    args = ["url.dll,FileProtocolHandler", url];
  } else if (process.platform === "darwin") {
    command = "open";
    args = [url];
  } else {
    command = "xdg-open";
    args = [url];
  }
  const child = spawn(command, args, {
    detached: true,
    stdio: "ignore",
    windowsHide: process.platform === "win32",
  });
  child.once("error", (error) => {
    console.error(`Could not open the browser automatically: ${error.message}`);
  });
  child.unref();
}

const server = http.createServer((request, response) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    noStore(response, 405, "Method not allowed");
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url ?? "/", "http://localhost").pathname);
  } catch {
    noStore(response, 400, "Bad request");
    return;
  }

  const relative = pathname.replace(/^\/+/, "") || "index.html";
  const file = path.resolve(root, relative);
  if (file !== root && !file.startsWith(`${root}${path.sep}`)) {
    noStore(response, 403, "Forbidden");
    return;
  }

  fs.readFile(file, (error, data) => {
    if (error) {
      noStore(response, 404, "Not found");
      return;
    }
    const type = types.get(path.extname(file).toLowerCase()) ?? "application/octet-stream";
    response.writeHead(200, {
      "cache-control": "no-store, max-age=0",
      "content-length": data.length,
      "content-type": type,
      "x-content-type-options": "nosniff",
    });
    if (request.method === "HEAD") response.end();
    else response.end(data);
  });
});

const multiplayer = attachMultiplayer(server, {
  authority,
  seed: BigInt(multiplayerSeedText),
  file: multiplayerFile,
  createServerWorld,
  // PEACEFUL=1 hosts a world without monsters.
  peaceful: process.env.PEACEFUL === "1",
});

const nativeBridge = nativePort === 0
  ? null
  : attachNativeBridge(multiplayer.room, { host, port: nativePort, log: (text) => console.error(text) });

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") {
    console.error(`Port ${port} is already in use. Close the old Bend2Craft server or set PORT to another port.`);
  } else {
    console.error(`Bend2Craft server error: ${error.message}`);
  }
  process.exitCode = 1;
});

server.listen(port, host, () => {
  const displayHost = host === "0.0.0.0" || host === "::" ? "localhost" : host;
  const url = `http://${displayHost}:${port}/?play=1&seed=1337&renderer=webgl`;
  console.log(`Bend2Craft at ${url}`);
  console.log(`Serving ${root} with browser caching disabled.`);
  const multiplayerSeed = multiplayer.seed.toString();
  console.log(`Multiplayer world (seed ${multiplayerSeed}) saved to ${multiplayerFile}.`);
  console.log(`Join it at http://${displayHost}:${port}/?play=1&mp=1`);
  if (nativeBridge !== null) {
    console.log(`Native clients join it with: bash scripts/play-native.sh --join=${displayHost === "localhost" ? "127.0.0.1" : displayHost}:${nativePort}`);
  }
  if (host === "0.0.0.0" || host === "::") {
    for (const address of lanAddresses()) console.log(`Friends on your network: http://${address}:${port}/?play=1&mp=1`);
  } else {
    console.log("Only this computer can join; start with --lan to let your network in.");
  }
  console.log("Press Ctrl+C to stop.");
  if (shouldOpenBrowser) openBrowser(url);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, () => {
    multiplayer.flush();
    nativeBridge?.close();
    server.close(() => process.exit(0));
    server.closeAllConnections?.();
    setTimeout(() => process.exit(0), 1000).unref();
  });
}
