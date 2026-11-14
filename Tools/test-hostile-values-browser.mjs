#!/usr/bin/env bun
// Values an application can receive from the network (far dates, huge or fractional numbers, deep JSON, odd URLs) run in
// the Embedded build of Tests/HostileValues, where `Int` is 32 bits: a conversion bounded for 64 bits passes the native
// tests and traps here. Each button runs one case in a fresh page; none may stop the app, and the answers that matter
// are checked. Usage: bun Tools/test-hostile-values-browser.mjs <bundle folder>
import assert from "node:assert/strict";
import { launch, runSuite, serveBundle } from "./browser-test-support.mjs";

// Cases whose answer is part of the contract; every other case only has to answer without trapping.
const EXPECTED = {
  "calendar-2038": "2065-1-24",
  "relative-3e9": "in 95 years",
  "distant-future-relative": "in 2032 years | 63113904000.0",
  "duration-int64-min": "15250284452471w 3d 15h 30m 8s",
  "json-int-3e9": "error",
  "json-int-frac": "error",
  "json-int-1e300": "error",
  "json-int64-uint8": "error",
  "json-deep": "error",
  "timezone": "-1 -1",
  "url-host": "evil,ok.example,evil.example",
  "url-append-component": "https://api.example.test/users/42%3Frole=admin%23x",
  "regex-ignorecase-eszett": "true",
  "regex-long-run": "false",
  "nsnumber-int-3e9": "true true",
  "calendar-add-month-far": "nil",
  "cookie-2040": "set",
  "replacing-many-cr": "fast",
  "json-fuzz": "3000 answered",
  "format-huge-width": "100000 100002",
  "regex-allowlist-lines": "false",
  "regex-catastrophic": "false",
  "regex-nested-groups": "refused",
  "cmtime-huge": "true",
  "url-query-in-fragment": "nil",
  "url-components-authority": "nil",
  "uicolor-nan": "made",
  "attributed-fold": "true",
  "int64-number": "3,000,000,000",
  "duration-time": "4,320:05 -01:02:03.456",
};

await runSuite(async () => {
  const bundle = process.argv[2];
  assert.ok(bundle, "usage: test-hostile-values-browser.mjs <bundle folder>");
  const server = await serveBundle({ bundle, logName: "hostile-values" });
  const browser = await launch();
  try {
    const open = async () => {
      const page = await browser.newPage();
      const failures = [];
      page.on("pageerror", (error) => failures.push(error.message));
      page.on("console", (message) => { if (message.type() === "error") failures.push(message.text()); });
      await page.goto(server.base);
      await page.getByText("idle").waitFor({ timeout: 60_000 });
      return { page, failures };
    };
    const first = await open();
    const labels = (await first.page.getByRole("button").allInnerTexts()).map((label) => label.trim());
    await first.page.close();
    assert.ok(labels.length > 40, `expected the hostile cases, found ${labels.length} buttons`);
    for (const label of labels) {
      const { page, failures } = await open();
      await page.getByRole("button", { name: label, exact: true }).click();
      const answered = await page.waitForFunction((name) => document.body.innerText.includes(name + ":"), label, { timeout: 10_000 })
        .then(() => true, () => false);
      // A trap that comes a moment after the answer (the next render) still fails the case.
      await page.waitForTimeout(250);
      const trapped = failures.find((text) => /unreachable|RuntimeError|trap|overflow|call stack/i.test(text));
      assert.ok(!trapped, `${label} trapped the app: ${trapped}`);
      assert.ok(answered, `${label} did not answer: ${failures.join(" | ") || "no page error"}`);
      const line = await page.evaluate((name) => document.body.innerText.split("\n").find((text) => text.startsWith(name + ":")), label);
      if (label in EXPECTED) assert.equal(line, `${label}: ${EXPECTED[label]}`);
      await page.close();
    }
    console.log(`PASS hostile values: ${labels.length} cases answer without trapping the Embedded build`);
  } finally {
    await browser.close();
    await server.stop();
  }
});
