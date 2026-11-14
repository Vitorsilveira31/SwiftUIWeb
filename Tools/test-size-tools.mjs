#!/usr/bin/env bun
// The size tools: Tools/measure-bundle.mjs, Tools/wasm-size.mjs (the baseline check) and
// Tools/wasm-function-sizes.mjs. The expected text is a checked-in golden, produced from the same inputs (with the
// `brotli` module).
import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, realpathSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { brotliCompressSync, constants, gzipSync } from "node:zlib";
import { inventory } from "./measure-bundle.mjs";
import { check as checkSize } from "./wasm-size.mjs";
import { diff, moduleOf, kindOf, parse, summarize } from "./wasm-function-sizes.mjs";
import { capture, finish, ROOT, test, withTemporary } from "./measurement-test-support.mjs";

const EMPTY_WASM = Buffer.from("0061736d01000000", "hex");

/** A bundle with nested directories, an odd sort order, hidden files, a link and non-ASCII names. */
export function writeBundle(root) {
  const put = (path, content) => {
    mkdirSync(join(root, path, ".."), { recursive: true });
    writeFileSync(join(root, path), content);
  };
  put("app.wasm", Buffer.concat([EMPTY_WASM, Buffer.from(Array.from({ length: 3000 }, (_, index) => (index * 7919) % 251))]));
  put("a-c.js", 'import "https://cdn.example.com/x.js?a=1&b=2"; // see http://foo.test/bar) ok\n'.repeat(50));
  put("a/b.js", 'const u="https://äpfel.test/é";');
  put("índex.html", '<a href="https://b.test/ü">日本語</a>'.repeat(20));
  put("s.css", "body{background:url(https://img.test/a.png)}");
  put("x.bin", Buffer.from(Array.from({ length: 10240 }, (_, index) => index % 256)));
  put(".hid/h.js", "hidden");
  put("app.js.map", "{}");
  put("lib.a", "abc");
  put("Z.JS", "upper");
  put("data.json", '{"u":"https://j.test/p"}');
  put("foo.size.json", "{}");
  put("release-size.json", "{}");
  put("noext", "noext");
  put(".dotfile", "d");
  symlinkSync(join(root, "s.css"), join(root, "link.css"));
}

/** A wasm module with one function import, a memory import, three bodies (one over 4 KB) and a name section. */
export function wasmModule({ names = true, big = 9000, extraName = "" } = {}) {
  const leb = (value) => {
    const bytes = [];
    let rest = value;
    do {
      let byte = rest & 0x7f;
      rest >>>= 7;
      if (rest) byte |= 0x80;
      bytes.push(byte);
    } while (rest);
    return Buffer.from(bytes);
  };
  const text = (value) => Buffer.concat([leb(Buffer.byteLength(value)), Buffer.from(value)]);
  const section = (kind, payload) => Buffer.concat([Buffer.from([kind]), leb(payload.length), payload]);
  const body = (size) => Buffer.concat([leb(size), Buffer.from([0]), Buffer.alloc(size - 2, 1), Buffer.from([0x0b])]);
  const parts = [
    EMPTY_WASM,
    section(1, Buffer.from([1, 0x60, 0, 0])),
    section(2, Buffer.concat([Buffer.from([2]), text("env"), text("f"), Buffer.from([0, 0]), text("env"), text("memory"), Buffer.from([2, 0, 1])])),
    section(3, Buffer.from([3, 0, 0, 0])),
    section(10, Buffer.concat([Buffer.from([3]), body(5), body(40), body(big)])),
  ];
  if (names) {
    const entries = [[0, "browser_io_proto"], [1, "$s4CoreyyF"], [2, `$s4CoreyyFTg5${extraName}`], [3, "$s3AppSayxGAA1PRzlWTW"]];
    const functionNames = Buffer.concat([leb(entries.length), ...entries.map(([index, name]) => Buffer.concat([leb(index), text(name)]))]);
    const payload = Buffer.concat([text("name"), Buffer.from([0]), leb(2), text("m"), Buffer.from([1]), leb(functionNames.length), functionNames]);
    parts.push(section(0, payload));
  }
  return Buffer.concat(parts);
}

if (import.meta.main) {
  const GOLDEN = JSON.parse(`{
 "inventoryPaths": [
  "Z.JS",
  "a/b.js",
  "a-c.js",
  "app.wasm",
  "data.json",
  "noext",
  "s.css",
  "x.bin",
  "índex.html"
 ],
 "inventoryExcluded": [
  ".dotfile",
  ".hid/h.js",
  "app.js.map",
  "foo.size.json",
  "lib.a",
  "link.css",
  "release-size.json"
 ],
 "inventoryNumbers": "{\\"groups\\":{\\"other\\":{\\"raw\\":10274,\\"gzip\\":478,\\"brotli\\":263},\\"javascript\\":{\\"raw\\":3933,\\"gzip\\":172,\\"brotli\\":120},\\"wasm\\":{\\"raw\\":3008,\\"gzip\\":317,\\"brotli\\":249},\\"css\\":{\\"raw\\":44,\\"gzip\\":64,\\"brotli\\":42},\\"html\\":{\\"raw\\":820,\\"gzip\\":71,\\"brotli\\":45}},\\"total\\":{\\"raw\\":18079,\\"gzip\\":1102,\\"brotli\\":719}}",
 "inventoryUrls": [
  "http://foo.test/bar",
  "https://b.test/ü",
  "https://cdn.example.com/x.js?a=1&b=2",
  "https://img.test/a.png",
  "https://j.test/p",
  "https://äpfel.test/é"
 ],
 "inventoryHashes": [
  "aee610558292023758a4229ddcf75f167c9904313a83cf795232ed7f7e2131c9",
  "75593bb7ead0aaaf63e865379126ee6ac08a74e5d01a748b79ed06451f5a40e8",
  "797fd30b214d2a17478a8f9e80a973b5cbfbac721d2fdd506b7c2e273ae24f2d",
  "ba8a59a4970152a2c985fe6eb07ffff0277ef7128b2808a71f0c6724d45db7f8",
  "554e28b237e6d03f99c07a532b05589dbba64df3f51f7cd3c746e12219214919",
  "c847f078e2b250f0794ec0ba4d44e516f4809240fe31024cdebf5702b9296d39",
  "ba0aa01633a0b4f1237aaf2079bde362faa217464e538ad6806621f6a9bc7d34",
  "e96760a87768717bcebcfd25ddc7d46b4dbc95a4b0014def080c08539f7d90d0",
  "952d62f22756071dadabce120e895a7a47aebe6b6640a580dc7f8fe36a855ef1"
 ],
 "inventoryStdout": "file                                                                  raw B       gzip B     Brotli B\\nZ.JS                                                                      5           25            9\\na/b.js                                                                   33           53           37\\na-c.js                                                                 3900          119           83\\napp.wasm                                                               3008          317          249\\ndata.json                                                                24           44           28\\nnoext                                                                     5           25            9\\ns.css                                                                    44           64           42\\nx.bin                                                                 10240          384          217\\níndex.html                                                              820           71           45\\n\\nGroups: {\\"other\\": {\\"raw\\": 10274, \\"gzip\\": 478, \\"brotli\\": 263}, \\"javascript\\": {\\"raw\\": 3933, \\"gzip\\": 172, \\"brotli\\": 120}, \\"wasm\\": {\\"raw\\": 3008, \\"gzip\\": 317, \\"brotli\\": 249}, \\"css\\": {\\"raw\\": 44, \\"gzip\\": 64, \\"brotli\\": 42}, \\"html\\": {\\"raw\\": 820, \\"gzip\\": 71, \\"brotli\\": 45}}\\nTotal local files: {\\"raw\\": 18079, \\"gzip\\": 1102, \\"brotli\\": 719}\\nNo HTTP/network transfer was measured. Check external_url_candidates in the JSON report.\\nJSON: DIR/out/report.json\\n",
 "sizeCheck": "raw      previous=      1000 current=      1100 delta=+100 (+10.00%) limit=+2.50% ABOVE\\ngzip9    previous=       400 current=       399 delta=-1 (-0.25%) limit=+2.50% OK\\nbrotli11 previous=       300 current=       300 delta=+0 (+0.00%) limit=+2.50% OK\\nzstd19   previous=       333 current=       340 delta=+7 (+2.10%) limit=+2.50% OK\\nzstd22   previous=       340 current=       100 delta=-240 (-70.59%) limit=+2.50% OK\\nREPORT Embedded Wasm size grew more than +2.50% over the baseline.",
 "summaryNamed": "named.wasm: 9,180 bytes, 3 functions, 9,045 code bytes, names=yes\\n  size percentiles: p50=40 p90=9000 p99=9000 max=9000; functions >4KB: 1, bytes in them: 9,000\\n  by module:\\n         9,000       1  App\\n            45       2  Core\\n  by kind:\\n         9,000       1  protocol-witness\\n            40       1  generic-specialization\\n             5       1  plain\\n  top 2 functions:\\n       9,000  $s3AppSayxGAA1PRzlWTW\\n          40  $s4CoreyyFTg5",
 "summaryStripped": "stripped.wasm: 9,098 bytes, 3 functions, 9,045 code bytes, names=no\\n  size percentiles: p50=40 p90=9000 p99=9000 max=9000; functions >4KB: 1, bytes in them: 9,000",
 "diff": "functions: 3 -> 3 (+1 new, -1 gone); code bytes 9,045 -> 9,145\\n  delta by module:\\n           +100  App\\n             +0  Core\\n  top 5 growth:\\n         +100  (9,000 -> 9,100)  $s3AppSayxGAA1PRzlWTW\\n          +40  (0 -> 40)  $s4CoreyyFTg5Q\\n          -40  (40 -> 0)  $s4CoreyyFTg5",
 "reportJson": "{\\"file\\": \\"named.wasm\\", \\"bytes\\": 9180, \\"functions\\": [[\\"$s4CoreyyF\\", 5], [\\"$s4CoreyyFTg5\\", 40], [\\"$s3AppSayxGAA1PRzlWTW\\", 9000]], \\"named\\": true}"
}`);

  await test("a directory without a wasm file is not a bundle", () =>
    withTemporary((directory) => {
      assert.throws(() => inventory(directory), /no final \.wasm/);
      assert.throws(() => inventory(join(directory, "missing")), (error) => error.code === "ENOENT");
    }));

  await test("a wasm file inside a hidden directory is not a bundle", () =>
    withTemporary((directory) => {
      mkdirSync(join(directory, ".cache"));
      writeFileSync(join(directory, ".cache/old.wasm"), EMPTY_WASM);
      assert.throws(() => inventory(directory), /no final \.wasm among deployable files/);
    }));

  await test("the inventory counts lazy assets and excludes archives, maps, hidden files and its own report", () =>
    withTemporary((directory) => {
      const js = Buffer.from('import("./lazy.js"); const url = "https://example.test/runtime.js";');
      writeFileSync(join(directory, "app.wasm"), EMPTY_WASM);
      writeFileSync(join(directory, "app.js"), js);
      writeFileSync(join(directory, "lazy.js"), "export default 1;");
      writeFileSync(join(directory, "extra.a"), "not shipped");
      writeFileSync(join(directory, "app.js.map"), "{}");
      writeFileSync(join(directory, "release-size.json"), '{"report":true}');
      mkdirSync(join(directory, ".old"));
      writeFileSync(join(directory, ".old/old.wasm"), EMPTY_WASM);
      const { result } = inventory(directory, { output: join(directory, "inventory.json") });
      const files = Object.fromEntries(result.files.map((file) => [file.path, file]));
      assert.deepEqual(Object.keys(files).sort(), ["app.js", "app.wasm", "lazy.js"]);
      assert.equal(files["app.wasm"].bytes.raw, 8);
      assert.equal(files["app.wasm"].bytes.gzip, gzipSync(EMPTY_WASM, { level: 9 }).length);
      assert.equal(files["app.wasm"].bytes.brotli, brotliCompressSync(EMPTY_WASM, { params: { [constants.BROTLI_PARAM_QUALITY]: 11, [constants.BROTLI_PARAM_MODE]: constants.BROTLI_MODE_GENERIC } }).length);
      assert.ok(result.external_url_candidates.includes("https://example.test/runtime.js"));
      assert.equal(result.complete_network_transfer_known, false);
      assert.equal(result.total_local_assets.raw, Object.values(files).reduce((sum, file) => sum + file.bytes.raw, 0));
    }));

  await test("the inventory report matches the golden, byte for byte (brotli included)", () =>
    withTemporary((directory) => {
      const bundle = join(directory, "bundle");
      mkdirSync(bundle);
      writeBundle(bundle);
      const output = join(directory, "out/report.json");
      const { result, rows, groups, total } = inventory(bundle, { output });
      assert.deepEqual(rows.map((row) => row.path), GOLDEN.inventoryPaths);
      assert.equal(JSON.stringify(result.excluded_files), JSON.stringify(GOLDEN.inventoryExcluded));
      assert.equal(JSON.stringify({ groups, total }), GOLDEN.inventoryNumbers);
      assert.deepEqual(result.external_url_candidates, GOLDEN.inventoryUrls);
      assert.deepEqual(rows.map((row) => row.sha256), GOLDEN.inventoryHashes);
      const cli = Bun.spawnSync(["bun", join(ROOT, "Tools/measure-bundle.mjs"), bundle, "--output", output], { stdout: "pipe", stderr: "pipe" });
      assert.equal(cli.exitCode, 0, cli.stderr.toString());
      assert.equal(cli.stdout.toString().replaceAll(realpathSync(directory), "DIR"), GOLDEN.inventoryStdout);
      assert.ok(existsSync(output));
    }));

  await test("the inventory command line exits 2 with the argparse-style message", () =>
    withTemporary((directory) => {
      const run = (...args) => Bun.spawnSync(["bun", join(ROOT, "Tools/measure-bundle.mjs"), ...args], { stdout: "pipe", stderr: "pipe" });
      let result = run(directory);
      assert.equal(result.exitCode, 2);
      assert.match(result.stderr.toString(), /measure-bundle\.mjs: error: no final \.wasm found/);
      result = run(join(directory, "missing"));
      assert.equal(result.exitCode, 2);
      assert.match(result.stderr.toString(), /error: bundle directory does not exist: .*missing\. Build the browser app first\./);
      result = run("");
      assert.equal(result.exitCode, 2);
      assert.match(result.stderr.toString(), /error: provide BUNDLE=\.build\/browser\/ShowcaseApp/);
      result = run(directory, "--brotli-quality", "12");
      assert.equal(result.exitCode, 2);
      assert.match(result.stderr.toString(), /argument --brotli-quality: invalid choice: '12' \(choose from 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11\)/);
      assert.equal(run().exitCode, 2);
    }));

  await test("a size regression against the baseline is reported without failing", () =>
    withTemporary((directory) => {
      const baseline = join(directory, "baseline.json");
      writeFileSync(baseline, JSON.stringify({ metrics: { raw: 100 }, maxPercentRegression: 5 }));
      const lines = [];
      const status = checkSize({ baseline }, { metrics: { raw: 106 } }, (line) => lines.push(line), () => assert.fail("no error output"));
      // Size is a target, not a gate: growth over the tolerance is reported and the check still passes.
      assert.equal(status, 0);
      assert.match(lines.join("\n"), /ABOVE/);
      assert.match(lines.join("\n"), /REPORT/);
    }));

  await test("growth within the tolerance passes quietly", () =>
    withTemporary((directory) => {
      const baseline = join(directory, "baseline.json");
      writeFileSync(baseline, JSON.stringify({ metrics: { raw: 100 }, maxPercentRegression: 5 }));
      const lines = [];
      assert.equal(checkSize({ baseline }, { metrics: { raw: 105 } }, (line) => lines.push(line)), 0);
      assert.ok(!lines.join("\n").includes("FAIL"));
      assert.ok(!lines.join("\n").includes("ABOVE"));
    }));

  await test("the size check prints the same table as the golden and a missing baseline is status 1", () =>
    withTemporary((directory) => {
      const baseline = join(directory, "baseline.json");
      writeFileSync(baseline, JSON.stringify({ metrics: { raw: 1000, gzip9: 400, brotli11: 300, zstd19: 333, zstd22: 340 }, code: 900, data: 100, maxPercentRegression: 2.5 }));
      const report = { metrics: { raw: 1100, gzip9: 399, brotli11: 300, zstd19: 340, zstd22: 100 }, code: 950, data: 100 };
      const lines = [];
      assert.equal(checkSize({ baseline }, report, (line) => lines.push(line)), 0);
      assert.equal(lines.join("\n"), GOLDEN.sizeCheck);
      const errors = [];
      assert.equal(checkSize({ baseline: join(directory, "none.json") }, report, () => {}, (line) => errors.push(line)), 1);
      assert.match(errors[0], /Missing checked-in baseline: .*none\.json/);
    }));

  await test("make wasm-size and bundle-sizes run the Bun tools", () => {
    const text = (target) => Bun.spawnSync(["make", "-n", target, "BUNDLE=x"], { cwd: ROOT, stdout: "pipe", stderr: "pipe" }).stdout.toString();
    assert.match(text("wasm-size"), /bun Tools\/wasm-size\.mjs/);
    assert.match(text("wasm-size-check"), /bun Tools\/wasm-size\.mjs --check/);
    assert.match(text("bundle-sizes"), /bun Tools\/measure-bundle\.mjs "x"/);
    assert.match(text("wasm-budget"), /--max-brotli "3000000"/);
  });

  await test("the function size report matches the golden on a named module", () =>
    withTemporary((directory) => {
      const path = join(directory, "named.wasm");
      writeFileSync(path, wasmModule());
      const report = parse(path);
      assert.equal(report.bytes, wasmModule().length);
      assert.equal(JSON.stringify(report.functions), JSON.stringify([["$s4CoreyyF", 5], ["$s4CoreyyFTg5", 40], ["$s3AppSayxGAA1PRzlWTW", 9000]]));
      const text = capture(() => summarize({ ...report, file: "named.wasm" }, 2)).out;
      assert.equal(text, GOLDEN.summaryNamed);
      const jsonPath = join(directory, "report.json");
      const cli = Bun.spawnSync(["bun", join(ROOT, "Tools/wasm-function-sizes.mjs"), "named.wasm", "--top", "2", "--json", "report.json"], { cwd: directory, stdout: "pipe", stderr: "pipe" });
      assert.equal(cli.exitCode, 0, cli.stderr.toString());
      assert.equal(cli.stdout.toString().trimEnd(), GOLDEN.summaryNamed);
      assert.equal(readFileSync(jsonPath, "utf8"), GOLDEN.reportJson);
    }));

  await test("a module without names still reports the function count and size distribution", () =>
    withTemporary((directory) => {
      const path = join(directory, "stripped.wasm");
      writeFileSync(path, wasmModule({ names: false }));
      const report = parse(path);
      assert.equal(report.named, false);
      assert.deepEqual(report.functions.map(([name]) => name), ["func[1]", "func[2]", "func[3]"]);
      assert.equal(capture(() => summarize({ ...report, file: "stripped.wasm" }, 5)).out, GOLDEN.summaryStripped);
    }));

  await test("two reports diff by symbol name", () =>
    withTemporary((directory) => {
      const before = join(directory, "before.wasm");
      const after = join(directory, "after.wasm");
      writeFileSync(before, wasmModule());
      writeFileSync(after, wasmModule({ big: 9100, extraName: "Q" }));
      assert.equal(capture(() => diff(parse(before), parse(after), 5)).out, GOLDEN.diff);
      const cli = Bun.spawnSync(["bun", join(ROOT, "Tools/wasm-function-sizes.mjs"), "--diff", before, after], { stdout: "pipe", stderr: "pipe" });
      assert.equal(cli.exitCode, 1, "a wasm file is not a JSON report");
    }));

  await test("symbols are grouped by module and kind", () => {
    assert.equal(moduleOf("$s4CoreyyF"), "Core");
    assert.equal(moduleOf("$s0x"), "?");
    assert.equal(moduleOf("embedded_core_x"), "host-abi");
    assert.equal(moduleOf("_ZN4core3fmt"), "c++");
    assert.equal(moduleOf("swift_retain"), "swift-runtime");
    assert.equal(moduleOf("func[12]"), "(unnamed)");
    assert.equal(moduleOf("memcpy"), "c/other");
    assert.equal(kindOf("memcpy"), "non-swift");
    assert.equal(kindOf("$s4CoreyyFTg5"), "generic-specialization");
    assert.equal(kindOf("$s4CorexTW"), "protocol-witness");
    assert.equal(kindOf("$s4CorexTf"), "thunk/specialized");
    assert.equal(kindOf("$s4CoreyyF"), "plain");
  });

  finish();
}
