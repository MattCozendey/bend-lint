// A minimal, dependency-free WebSocket server endpoint (RFC 6455) for Node's
// http server: text frames only, client frames must be masked, fragmented
// messages are reassembled, pings are answered, and idle peers are dropped.
import { createHash } from "node:crypto";

const HANDSHAKE_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const OPCODE_CONTINUATION = 0x0;
const OPCODE_TEXT = 0x1;
const OPCODE_BINARY = 0x2;
const OPCODE_CLOSE = 0x8;
const OPCODE_PING = 0x9;
const OPCODE_PONG = 0xa;

export function acceptKey(key) {
  return createHash("sha1").update(`${key}${HANDSHAKE_GUID}`).digest("base64");
}

export function encodeFrame(opcode, payload) {
  const body = Buffer.isBuffer(payload) ? payload : Buffer.from(payload ?? "", "utf8");
  let header;
  if (body.length < 126) {
    header = Buffer.from([0x80 | opcode, body.length]);
  } else if (body.length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(body.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(body.length), 2);
  }
  return Buffer.concat([header, body]);
}

function closePayload(code, reason = "") {
  const text = Buffer.from(String(reason).slice(0, 120), "utf8");
  const payload = Buffer.alloc(2 + text.length);
  payload.writeUInt16BE(code, 0);
  text.copy(payload, 2);
  return payload;
}

/**
 * Completes the upgrade handshake on `socket` and returns a connection, or
 * null after answering the request with an error.
 */
export function acceptWebSocket(request, socket, head, {
  maxPayload = 1024 * 1024,
  heartbeatMs = 30_000,
  onMessage = () => {},
  onClose = () => {},
} = {}) {
  const key = request.headers["sec-websocket-key"];
  const upgrade = String(request.headers.upgrade ?? "").toLowerCase();
  if (request.method !== "GET" || upgrade !== "websocket" || typeof key !== "string"
    || request.headers["sec-websocket-version"] !== "13") {
    socket.end("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n");
    return null;
  }
  socket.write([
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    `Sec-WebSocket-Accept: ${acceptKey(key)}`,
    "",
    "",
  ].join("\r\n"));
  socket.setNoDelay(true);

  let buffer = head?.length ? Buffer.from(head) : Buffer.alloc(0);
  let fragments = [];
  let fragmentBytes = 0;
  let open = true;
  let alive = true;

  function write(opcode, payload) {
    if (!open || socket.destroyed) return false;
    socket.write(encodeFrame(opcode, payload));
    return true;
  }

  function finish() {
    if (!open) return;
    open = false;
    clearInterval(heartbeat);
    onClose();
  }

  function close(code = 1000, reason = "") {
    if (!open) return;
    write(OPCODE_CLOSE, closePayload(code, reason));
    finish();
    socket.end();
  }

  function fail(code, reason) {
    close(code, reason);
    setTimeout(() => socket.destroy(), 1000).unref?.();
  }

  function handleFrame(fin, opcode, payload) {
    if (opcode === OPCODE_PING) {
      write(OPCODE_PONG, payload);
      return;
    }
    if (opcode === OPCODE_PONG) {
      alive = true;
      return;
    }
    if (opcode === OPCODE_CLOSE) {
      const code = payload.length >= 2 ? payload.readUInt16BE(0) : 1000;
      close(code === 1005 || code === 1006 ? 1000 : code);
      return;
    }
    if (opcode === OPCODE_BINARY) {
      fail(1003, "Text frames only");
      return;
    }
    if (opcode === OPCODE_TEXT) {
      if (fragments.length > 0) {
        fail(1002, "Unexpected new message");
        return;
      }
    } else if (opcode === OPCODE_CONTINUATION) {
      if (fragments.length === 0) {
        fail(1002, "Unexpected continuation");
        return;
      }
    } else {
      fail(1002, "Unknown opcode");
      return;
    }
    fragments.push(payload);
    fragmentBytes += payload.length;
    if (fragmentBytes > maxPayload) {
      fail(1009, "Message too big");
      return;
    }
    if (!fin) return;
    const text = Buffer.concat(fragments).toString("utf8");
    fragments = [];
    fragmentBytes = 0;
    onMessage(text);
  }

  function drain() {
    while (open && buffer.length >= 2) {
      const first = buffer[0];
      const second = buffer[1];
      const fin = (first & 0x80) !== 0;
      const opcode = first & 0x0f;
      const masked = (second & 0x80) !== 0;
      let length = second & 0x7f;
      let offset = 2;
      if (!masked) {
        fail(1002, "Client frames must be masked");
        return;
      }
      if (length === 126) {
        if (buffer.length < 4) return;
        length = buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (buffer.length < 10) return;
        const big = buffer.readBigUInt64BE(2);
        if (big > BigInt(maxPayload)) {
          fail(1009, "Message too big");
          return;
        }
        length = Number(big);
        offset = 10;
      }
      if (length > maxPayload) {
        fail(1009, "Message too big");
        return;
      }
      if ((opcode & 0x08) !== 0 && (length > 125 || !fin)) {
        fail(1002, "Invalid control frame");
        return;
      }
      if (buffer.length < offset + 4 + length) return;
      const mask = buffer.subarray(offset, offset + 4);
      const payload = Buffer.from(buffer.subarray(offset + 4, offset + 4 + length));
      for (let index = 0; index < payload.length; index += 1) payload[index] ^= mask[index & 3];
      buffer = buffer.subarray(offset + 4 + length);
      handleFrame(fin, opcode, payload);
    }
  }

  socket.on("data", (chunk) => {
    buffer = buffer.length === 0 ? chunk : Buffer.concat([buffer, chunk]);
    drain();
  });
  socket.on("close", finish);
  socket.on("end", finish);
  socket.on("error", finish);

  const heartbeat = setInterval(() => {
    if (!alive) {
      finish();
      socket.destroy();
      return;
    }
    alive = false;
    write(OPCODE_PING, Buffer.alloc(0));
  }, heartbeatMs);
  heartbeat.unref?.();

  if (buffer.length > 0) queueMicrotask(drain);

  return {
    send: (text) => write(OPCODE_TEXT, Buffer.from(text, "utf8")),
    close,
    get open() { return open; },
  };
}
