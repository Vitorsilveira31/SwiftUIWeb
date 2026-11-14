#!/usr/bin/env bun
// Test Bun's deterministic port/error/cleanup contract without a WASM build.
import { spawn, spawnSync } from "node:child_process";
import { accessSync, constants, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { tmpdir, constants as osConstants } from "node:os";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TIMED_OUT = Symbol("timed-out");

function which(name) {
  for (const directory of (process.env.PATH ?? "").split(delimiter)) {
    if (!directory) continue;
    const candidate = join(directory, name);
    try {
      if (!statSync(candidate).isFile()) continue;
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      // Not an executable file here; keep searching PATH.
    }
  }
  return null;
}

function freePort() {
  return new Promise((resolvePort, reject) => {
    const server = net.createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolvePort(port));
    });
  });
}

// Collects stdout and stderr together, and
// keeps a promise that settles once the process has exited and its pipes closed.
function capture(child) {
  const state = { text: "", closed: null };
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => {
    state.text += chunk;
  });
  child.stderr.on("data", (chunk) => {
    state.text += chunk;
  });
  state.closed = new Promise((resolveClose) => {
    child.once("close", (code, signal) => resolveClose({ code, signal }));
  });
  return state;
}

function exitedAlready(child) {
  return child.exitCode !== null || child.signalCode !== null;
}

function sleep(ms) {
  return new Promise((resolveSleep) => setTimeout(resolveSleep, ms));
}

function waitFor(promise, ms) {
  let timer;
  const timeout = new Promise((resolveTimeout) => {
    timer = setTimeout(() => resolveTimeout(TIMED_OUT), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function httpStatus(port) {
  return new Promise((resolveStatus, reject) => {
    const request = http.get({ host: "127.0.0.1", port, path: "/", timeout: 500 }, (response) => {
      response.resume();
      response.on("end", () => resolveStatus(response.statusCode));
      response.on("error", reject);
    });
    request.on("timeout", () => request.destroy(new Error("timed out")));
    request.on("error", reject);
  });
}

async function waitForHttp(port, child, state) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    if (exitedAlready(child)) {
      const result = await state.closed;
      throw new Error(
        `server exited before startup (${result.code ?? result.signal}): ${state.text}`,
      );
    }
    try {
      const status = await httpStatus(port);
      if (status === 200) return;
    } catch {
      // Connection refused or timed out while the server is still binding; retry.
    }
    await sleep(100);
  }
  throw new Error(`server did not bind port ${port}`);
}

async function stop(child, state) {
  if (!exitedAlready(child)) child.kill("SIGINT");
  let result = await waitFor(state.closed, 5_000);
  if (result === TIMED_OUT) {
    child.kill("SIGKILL");
    result = await waitFor(state.closed, 5_000);
    if (result === TIMED_OUT) throw new Error("server did not exit after SIGKILL");
  }
  // A signal death is reported as -signum.
  const code = result.code ?? -osConstants.signals[result.signal];
  return { code, output: state.text };
}

function canConnect(port) {
  return new Promise((resolveConnect) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    socket.setTimeout(500);
    socket.once("connect", () => {
      socket.destroy();
      resolveConnect(true);
    });
    socket.once("error", () => {
      socket.destroy();
      resolveConnect(false);
    });
    socket.once("timeout", () => {
      socket.destroy();
      resolveConnect(false);
    });
  });
}

async function main() {
  const bun = which("bun");
  if (!bun) throw new Error("test-server-lifecycle: Bun is required");
  const root = mkdtempSync(join(tmpdir(), "swiftuiweb-server-"));
  try {
    writeFileSync(join(root, "index.html"), "<!doctype html><title>SwiftUIWeb</title>\n", "utf8");
    const port = await freePort();
    const command = [bun, "Tools/bun-server.ts", root, String(port)];
    const first = spawn(command[0], command.slice(1), {
      cwd: ROOT,
      env: { ...process.env, PORT: String(port) },
      stdio: ["inherit", "pipe", "pipe"],
    });
    const state = capture(first);
    try {
      await waitForHttp(port, first, state);
      const second = spawnSync(command[0], command.slice(1), {
        cwd: ROOT,
        encoding: "utf8",
      });
      if (second.error) throw second.error;
      const secondOutput = second.stdout + second.stderr;
      if (second.status === 0 || !secondOutput.includes("EADDRINUSE")) {
        throw new Error(
          `occupied-port contract failed: status=${second.status ?? second.signal}\n${secondOutput}`,
        );
      }
    } finally {
      const { code, output } = await stop(first, state);
      if (![0, -2, 130, 143].includes(code)) {
        throw new Error(`server did not stop cleanly (${code}): ${output}`);
      }
    }
    if (await canConnect(port)) {
      throw new Error("server still owns the port after Ctrl-C");
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
  console.log("Bun server lifecycle: startup, occupied-port error, and Ctrl-C cleanup passed");
  return 0;
}

main().then(
  (code) => {
    process.exitCode = code;
  },
  (error) => {
    console.error(error.message);
    process.exitCode = 1;
  },
);
