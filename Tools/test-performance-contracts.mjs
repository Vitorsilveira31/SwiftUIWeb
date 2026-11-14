#!/usr/bin/env bun
// Tools/performance-contracts.mjs: the metric collectors, the report merge, the budget check and the markdown report.
// The expected files are checked-in goldens, produced over the same fixture root.
import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { check, collectArtifact, collectSwift, defaultContext, ExitError, getPath, main, mergeReport, parseKv } from "./performance-contracts.mjs";
import { Float } from "./format-compat.mjs";
import { capture, finish, ROOT, test, withTemporary } from "./measurement-test-support.mjs";

export const SWIFT_LOG = [
  "Test run started.",
  "startup,renderNodeLive=1,fiberLive=1,stateBoxes=1,stateStorage=1,liveObjects=7,retainedNodeBytes=2048",
  "memory,allocations=10,deallocations=9,renderNodeLive=1,peakRenderNodeLive=3,fiberAllocations=2,fiberLive=1,bindingCells=0,stateBoxes=1,stateStorage=1,stateEntries=1,dependencyEdges=0,liveObjects=1,arcEvents=40,retainedNodeBytes=1024,estimatedBytes=4096.5",
  "list-scale,count=100,startupLive=1,peakLive=200,settledLive=100,peakBytes=2000",
  "list-scale,count=10000,startupLive=1,peakLive=20000,settledLive=10000,peakBytes=2000000",
  "list-scale,count=1000,startupLive=1,peakLive=2000,settledLive=1000,peakBytes=200000",
  "release,renderNodeLive=0,fiberLive=0,bindingCellLive=0,retainedNodeBytes=0",
  "list-removal,removed=100,livePerRemoved=1.0,ratio=2e-3",
  "noise without fields",
  "",
].join("\n");

const SHOWCASE_SIZE = {
  initial: { raw: 3000000, gzip: 1000000, brotli: 700000 },
  lazy: { raw: 100, gzip: 60, brotli: 50 },
};

const BUDGETS = {
  budgets: [
    { name: "initial-brotli-wasm", path: "artifacts.ShowcaseApp.initial.brotli", unit: "bytes", max: 650000, source: "artifact-size", enforcement: "report" },
    { name: "artifact-regression", path: "artifacts.ShowcaseApp.all.gzip", unit: "bytes", max: 1100000, maxRegressionPercent: 5, source: "artifact-size" },
    { name: "list-startup", path: "browser.fixtures.list.startup.timeToInteractiveMs", unit: "ms", max: 200, maxRegressionPercent: 10, source: "browser" },
    { name: "list-dom-mutations", path: "browser.fixtures.list.interactions.update.domMutations.median", unit: "mutations", max: 12, source: "browser" },
    { name: "embedded-startup", path: "embeddedBrowser.scenarios.startup.elapsedMs", unit: "ms", max: 1000, source: "browser" },
    { name: "released-render-nodes", path: "swift.release.renderNodeLive", unit: "nodes", max: 0, source: "swift-memory" },
    { name: "list-10000-peak", path: "swift.listScale.10000.peakBytes", unit: "bytes", max: 3000000, source: "swift-memory" },
  ],
};

const ARTIFACT_BASELINE = {
  schemaVersion: 1,
  artifacts: [{ name: "ShowcaseApp", status: "ready", analysis: { totals: { initial: { raw: 3100000, gzip: 1010000, brotli: 710000 }, optional: { raw: 0, gzip: 0, brotli: 0 }, all: { raw: 3100000, gzip: 1010000, brotli: 710000 }, layout: { raw: 181000, gzip: 71000, brotli: 63000 } } } }],
};

const BROWSER_CURRENT = {
  schemaVersion: 1,
  fixtures: { list: { samples: [1, 2, 3], summary: { startup: { timeToInteractiveMs: 105.5 }, interactions: { update: { domMutations: { median: 5.0 } } } } }, other: { startup: { timeToInteractiveMs: 49 } } },
};

const EMBEDDED = { schemaVersion: 1, scenarios: { startup: { elapsedMs: 250.0, errors: 0 } } };

const write = (path, value) => {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, typeof value === "string" ? value : `${JSON.stringify(value, null, 2)}\n`);
};

/** A repository-shaped directory with budgets, baselines and the metrics a build would have left in `.build/performance`. */
export function fixtureRoot(root, { browserBuild = true } = {}) {
  const docs = join(root, "Documentation/Performance");
  write(join(docs, "PERFORMANCE_BUDGETS.json"), BUDGETS);
  write(join(docs, "BROWSER_ARTIFACT_SIZE_BASELINE.json"), ARTIFACT_BASELINE);
  write(join(root, "canned/swift-memory.log"), SWIFT_LOG);
  write(join(root, "canned/showcase-size.json"), SHOWCASE_SIZE);
  if (browserBuild) {
    write(join(root, ".build/performance/browser.json"), BROWSER_CURRENT);
    write(join(root, ".build/performance/embedded-browser.json"), EMBEDDED);
  }
  return root;
}

/** A context whose command runner answers from the fixture instead of running swift or the size report. */
export function cannedContext(root) {
  const ctx = defaultContext(root, {});
  ctx.run = (command, output) => {
    mkdirSync(join(output, ".."), { recursive: true });
    if (command.includes("MemoryBenchmarks")) {
      writeFileSync(output, SWIFT_LOG);
      return SWIFT_LOG;
    }
    copyFileSync(join(root, "canned/showcase-size.json"), join(ctx.build, "showcase-size.json"));
    writeFileSync(output, "");
    return "";
  };
  return ctx;
}

const read = (root, path) => readFileSync(join(root, ".build/performance", path), "utf8");
const mask = (text) => text.replace(/"generatedAt": "[^"]*"/, '"generatedAt": "T"').replace(/^Generated: .*$/m, "Generated: T");

if (import.meta.main) {
  const GOLDEN = JSON.parse(`{
 "swiftOut": "PASS performance contracts (2 budgets, scope=swift)",
 "swiftMetrics": "{\\n  \\"schemaVersion\\": 1,\\n  \\"namespace\\": \\"swift.runtime\\",\\n  \\"scenarios\\": {\\n    \\"listScale\\": {\\n      \\"100\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 200,\\n        \\"settledLive\\": 100,\\n        \\"peakBytes\\": 2000\\n      },\\n      \\"10000\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 20000,\\n        \\"settledLive\\": 10000,\\n        \\"peakBytes\\": 2000000\\n      },\\n      \\"1000\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 2000,\\n        \\"settledLive\\": 1000,\\n        \\"peakBytes\\": 200000\\n      }\\n    }\\n  },\\n  \\"startup\\": {\\n    \\"renderNodeLive\\": 1,\\n    \\"fiberLive\\": 1,\\n    \\"stateBoxes\\": 1,\\n    \\"stateStorage\\": 1,\\n    \\"liveObjects\\": 7,\\n    \\"retainedNodeBytes\\": 2048\\n  },\\n  \\"mutation\\": {\\n    \\"allocations\\": 10,\\n    \\"deallocations\\": 9,\\n    \\"renderNodeLive\\": 1,\\n    \\"peakRenderNodeLive\\": 3,\\n    \\"fiberAllocations\\": 2,\\n    \\"fiberLive\\": 1,\\n    \\"bindingCells\\": 0,\\n    \\"stateBoxes\\": 1,\\n    \\"stateStorage\\": 1,\\n    \\"stateEntries\\": 1,\\n    \\"dependencyEdges\\": 0,\\n    \\"liveObjects\\": 1,\\n    \\"arcEvents\\": 40,\\n    \\"retainedNodeBytes\\": 1024,\\n    \\"estimatedBytes\\": 4096.5\\n  },\\n  \\"release\\": {\\n    \\"renderNodeLive\\": 0,\\n    \\"fiberLive\\": 0,\\n    \\"bindingCellLive\\": 0,\\n    \\"retainedNodeBytes\\": 0\\n  },\\n  \\"listRemoval\\": {\\n    \\"removed\\": 100,\\n    \\"livePerRemoved\\": 1.0,\\n    \\"ratio\\": \\"2e-3\\"\\n  },\\n  \\"listScale\\": {\\n    \\"100\\": {\\n      \\"startupLive\\": 1,\\n      \\"peakLive\\": 200,\\n      \\"settledLive\\": 100,\\n      \\"peakBytes\\": 2000\\n    },\\n    \\"10000\\": {\\n      \\"startupLive\\": 1,\\n      \\"peakLive\\": 20000,\\n      \\"settledLive\\": 10000,\\n      \\"peakBytes\\": 2000000\\n    },\\n    \\"1000\\": {\\n      \\"startupLive\\": 1,\\n      \\"peakLive\\": 2000,\\n      \\"settledLive\\": 1000,\\n      \\"peakBytes\\": 200000\\n    }\\n  }\\n}\\n",
 "swiftReport": "{\\n  \\"schemaVersion\\": 1,\\n  \\"generatedAt\\": \\"T\\",\\n  \\"provenance\\": {\\n    \\"artifact\\": \\"checked-in-baseline\\",\\n    \\"browser\\": \\"build\\",\\n    \\"embeddedBrowser\\": \\"build\\",\\n    \\"swift\\": \\"build\\"\\n  },\\n  \\"artifacts\\": {\\n    \\"ShowcaseApp\\": {\\n      \\"initial\\": {\\n        \\"raw\\": 3100000,\\n        \\"gzip\\": 1010000,\\n        \\"brotli\\": 710000\\n      },\\n      \\"optional\\": {\\n        \\"raw\\": 0,\\n        \\"gzip\\": 0,\\n        \\"brotli\\": 0\\n      },\\n      \\"all\\": {\\n        \\"raw\\": 3100000,\\n        \\"gzip\\": 1010000,\\n        \\"brotli\\": 710000\\n      },\\n      \\"layout\\": {\\n        \\"raw\\": 181000,\\n        \\"gzip\\": 71000,\\n        \\"brotli\\": 63000\\n      }\\n    }\\n  },\\n  \\"browser\\": {\\n    \\"fixtures\\": {\\n      \\"list\\": {\\n        \\"startup\\": {\\n          \\"timeToInteractiveMs\\": 105.5\\n        },\\n        \\"interactions\\": {\\n          \\"update\\": {\\n            \\"domMutations\\": {\\n              \\"median\\": 5\\n            }\\n          }\\n        }\\n      },\\n      \\"other\\": {\\n        \\"startup\\": {\\n          \\"timeToInteractiveMs\\": 49\\n        }\\n      }\\n    }\\n  },\\n  \\"embeddedBrowser\\": {\\n    \\"schemaVersion\\": 1,\\n    \\"scenarios\\": {\\n      \\"startup\\": {\\n        \\"elapsedMs\\": 250,\\n        \\"errors\\": 0\\n      }\\n    }\\n  },\\n  \\"swift\\": {\\n    \\"schemaVersion\\": 1,\\n    \\"namespace\\": \\"swift.runtime\\",\\n    \\"scenarios\\": {\\n      \\"listScale\\": {\\n        \\"100\\": {\\n          \\"startupLive\\": 1,\\n          \\"peakLive\\": 200,\\n          \\"settledLive\\": 100,\\n          \\"peakBytes\\": 2000\\n        },\\n        \\"10000\\": {\\n          \\"startupLive\\": 1,\\n          \\"peakLive\\": 20000,\\n          \\"settledLive\\": 10000,\\n          \\"peakBytes\\": 2000000\\n        },\\n        \\"1000\\": {\\n          \\"startupLive\\": 1,\\n          \\"peakLive\\": 2000,\\n          \\"settledLive\\": 1000,\\n          \\"peakBytes\\": 200000\\n        }\\n      }\\n    },\\n    \\"startup\\": {\\n      \\"renderNodeLive\\": 1,\\n      \\"fiberLive\\": 1,\\n      \\"stateBoxes\\": 1,\\n      \\"stateStorage\\": 1,\\n      \\"liveObjects\\": 7,\\n      \\"retainedNodeBytes\\": 2048\\n    },\\n    \\"mutation\\": {\\n      \\"allocations\\": 10,\\n      \\"deallocations\\": 9,\\n      \\"renderNodeLive\\": 1,\\n      \\"peakRenderNodeLive\\": 3,\\n      \\"fiberAllocations\\": 2,\\n      \\"fiberLive\\": 1,\\n      \\"bindingCells\\": 0,\\n      \\"stateBoxes\\": 1,\\n      \\"stateStorage\\": 1,\\n      \\"stateEntries\\": 1,\\n      \\"dependencyEdges\\": 0,\\n      \\"liveObjects\\": 1,\\n      \\"arcEvents\\": 40,\\n      \\"retainedNodeBytes\\": 1024,\\n      \\"estimatedBytes\\": 4096.5\\n    },\\n    \\"release\\": {\\n      \\"renderNodeLive\\": 0,\\n      \\"fiberLive\\": 0,\\n      \\"bindingCellLive\\": 0,\\n      \\"retainedNodeBytes\\": 0\\n    },\\n    \\"listRemoval\\": {\\n      \\"removed\\": 100,\\n      \\"livePerRemoved\\": 1.0,\\n      \\"ratio\\": \\"2e-3\\"\\n    },\\n    \\"listScale\\": {\\n      \\"100\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 200,\\n        \\"settledLive\\": 100,\\n        \\"peakBytes\\": 2000\\n      },\\n      \\"10000\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 20000,\\n        \\"settledLive\\": 10000,\\n        \\"peakBytes\\": 2000000\\n      },\\n      \\"1000\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 2000,\\n        \\"settledLive\\": 1000,\\n        \\"peakBytes\\": 200000\\n      }\\n    }\\n  },\\n  \\"baseline\\": {\\n    \\"artifacts\\": {\\n      \\"ShowcaseApp\\": {\\n        \\"initial\\": {\\n          \\"raw\\": 3100000,\\n          \\"gzip\\": 1010000,\\n          \\"brotli\\": 710000\\n        },\\n        \\"optional\\": {\\n          \\"raw\\": 0,\\n          \\"gzip\\": 0,\\n          \\"brotli\\": 0\\n        },\\n        \\"all\\": {\\n          \\"raw\\": 3100000,\\n          \\"gzip\\": 1010000,\\n          \\"brotli\\": 710000\\n        },\\n        \\"layout\\": {\\n          \\"raw\\": 181000,\\n          \\"gzip\\": 71000,\\n          \\"brotli\\": 63000\\n        }\\n      }\\n    }\\n  },\\n  \\"deltas\\": {\\n    \\"artifacts\\": {\\n      \\"ShowcaseApp\\": {\\n        \\"initial\\": {\\n          \\"raw\\": 0,\\n          \\"gzip\\": 0,\\n          \\"brotli\\": 0\\n        },\\n        \\"optional\\": {\\n          \\"raw\\": 0,\\n          \\"gzip\\": 0,\\n          \\"brotli\\": 0\\n        },\\n        \\"all\\": {\\n          \\"raw\\": 0,\\n          \\"gzip\\": 0,\\n          \\"brotli\\": 0\\n        }\\n      }\\n    }\\n  }\\n}\\n",
 "browserOut": "REPORT initial-brotli-wasm: 700000 bytes, target 650000 (above target), baseline 710000 (-1.41%)\\nPASS performance contracts (4 budgets, scope=browser)",
 "artifactSize": "{\\n  \\"schemaVersion\\": 1,\\n  \\"artifacts\\": [\\n    {\\n      \\"name\\": \\"ShowcaseApp\\",\\n      \\"product\\": \\"ShowcaseApp\\",\\n      \\"bundle\\": \\"ROOT/.build/browser/ShowcaseApp\\",\\n      \\"status\\": \\"ready\\",\\n      \\"analysis\\": {\\n        \\"totals\\": {\\n          \\"initial\\": {\\n            \\"raw\\": 3000000,\\n            \\"gzip\\": 1000000,\\n            \\"brotli\\": 700000\\n          },\\n          \\"optional\\": {\\n            \\"raw\\": 100,\\n            \\"gzip\\": 60,\\n            \\"brotli\\": 50\\n          },\\n          \\"all\\": {\\n            \\"raw\\": 3000100,\\n            \\"gzip\\": 1000060,\\n            \\"brotli\\": 700050\\n          }\\n        }\\n      }\\n    }\\n  ]\\n}\\n",
 "browserReport": "{\\n  \\"schemaVersion\\": 1,\\n  \\"generatedAt\\": \\"T\\",\\n  \\"provenance\\": {\\n    \\"artifact\\": \\"build\\",\\n    \\"browser\\": \\"build\\",\\n    \\"embeddedBrowser\\": \\"build\\",\\n    \\"swift\\": \\"build\\"\\n  },\\n  \\"artifacts\\": {\\n    \\"ShowcaseApp\\": {\\n      \\"initial\\": {\\n        \\"raw\\": 3000000,\\n        \\"gzip\\": 1000000,\\n        \\"brotli\\": 700000\\n      },\\n      \\"optional\\": {\\n        \\"raw\\": 100,\\n        \\"gzip\\": 60,\\n        \\"brotli\\": 50\\n      },\\n      \\"all\\": {\\n        \\"raw\\": 3000100,\\n        \\"gzip\\": 1000060,\\n        \\"brotli\\": 700050\\n      }\\n    }\\n  },\\n  \\"browser\\": {\\n    \\"fixtures\\": {\\n      \\"list\\": {\\n        \\"startup\\": {\\n          \\"timeToInteractiveMs\\": 105.5\\n        },\\n        \\"interactions\\": {\\n          \\"update\\": {\\n            \\"domMutations\\": {\\n              \\"median\\": 5\\n            }\\n          }\\n        }\\n      },\\n      \\"other\\": {\\n        \\"startup\\": {\\n          \\"timeToInteractiveMs\\": 49\\n        }\\n      }\\n    }\\n  },\\n  \\"embeddedBrowser\\": {\\n    \\"schemaVersion\\": 1,\\n    \\"scenarios\\": {\\n      \\"startup\\": {\\n        \\"elapsedMs\\": 250,\\n        \\"errors\\": 0\\n      }\\n    }\\n  },\\n  \\"swift\\": {\\n    \\"schemaVersion\\": 1,\\n    \\"namespace\\": \\"swift.runtime\\",\\n    \\"scenarios\\": {\\n      \\"listScale\\": {\\n        \\"100\\": {\\n          \\"startupLive\\": 1,\\n          \\"peakLive\\": 200,\\n          \\"settledLive\\": 100,\\n          \\"peakBytes\\": 2000\\n        },\\n        \\"10000\\": {\\n          \\"startupLive\\": 1,\\n          \\"peakLive\\": 20000,\\n          \\"settledLive\\": 10000,\\n          \\"peakBytes\\": 2000000\\n        },\\n        \\"1000\\": {\\n          \\"startupLive\\": 1,\\n          \\"peakLive\\": 2000,\\n          \\"settledLive\\": 1000,\\n          \\"peakBytes\\": 200000\\n        }\\n      }\\n    },\\n    \\"startup\\": {\\n      \\"renderNodeLive\\": 1,\\n      \\"fiberLive\\": 1,\\n      \\"stateBoxes\\": 1,\\n      \\"stateStorage\\": 1,\\n      \\"liveObjects\\": 7,\\n      \\"retainedNodeBytes\\": 2048\\n    },\\n    \\"mutation\\": {\\n      \\"allocations\\": 10,\\n      \\"deallocations\\": 9,\\n      \\"renderNodeLive\\": 1,\\n      \\"peakRenderNodeLive\\": 3,\\n      \\"fiberAllocations\\": 2,\\n      \\"fiberLive\\": 1,\\n      \\"bindingCells\\": 0,\\n      \\"stateBoxes\\": 1,\\n      \\"stateStorage\\": 1,\\n      \\"stateEntries\\": 1,\\n      \\"dependencyEdges\\": 0,\\n      \\"liveObjects\\": 1,\\n      \\"arcEvents\\": 40,\\n      \\"retainedNodeBytes\\": 1024,\\n      \\"estimatedBytes\\": 4096.5\\n    },\\n    \\"release\\": {\\n      \\"renderNodeLive\\": 0,\\n      \\"fiberLive\\": 0,\\n      \\"bindingCellLive\\": 0,\\n      \\"retainedNodeBytes\\": 0\\n    },\\n    \\"listRemoval\\": {\\n      \\"removed\\": 100,\\n      \\"livePerRemoved\\": 1.0,\\n      \\"ratio\\": \\"2e-3\\"\\n    },\\n    \\"listScale\\": {\\n      \\"100\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 200,\\n        \\"settledLive\\": 100,\\n        \\"peakBytes\\": 2000\\n      },\\n      \\"10000\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 20000,\\n        \\"settledLive\\": 10000,\\n        \\"peakBytes\\": 2000000\\n      },\\n      \\"1000\\": {\\n        \\"startupLive\\": 1,\\n        \\"peakLive\\": 2000,\\n        \\"settledLive\\": 1000,\\n        \\"peakBytes\\": 200000\\n      }\\n    }\\n  },\\n  \\"baseline\\": {\\n    \\"artifacts\\": {\\n      \\"ShowcaseApp\\": {\\n        \\"initial\\": {\\n          \\"raw\\": 3100000,\\n          \\"gzip\\": 1010000,\\n          \\"brotli\\": 710000\\n        },\\n        \\"optional\\": {\\n          \\"raw\\": 0,\\n          \\"gzip\\": 0,\\n          \\"brotli\\": 0\\n        },\\n        \\"all\\": {\\n          \\"raw\\": 3100000,\\n          \\"gzip\\": 1010000,\\n          \\"brotli\\": 710000\\n        },\\n        \\"layout\\": {\\n          \\"raw\\": 181000,\\n          \\"gzip\\": 71000,\\n          \\"brotli\\": 63000\\n        }\\n      }\\n    }\\n  },\\n  \\"deltas\\": {\\n    \\"artifacts\\": {\\n      \\"ShowcaseApp\\": {\\n        \\"initial\\": {\\n          \\"raw\\": -100000,\\n          \\"gzip\\": -10000,\\n          \\"brotli\\": -10000\\n        },\\n        \\"optional\\": {\\n          \\"raw\\": 100,\\n          \\"gzip\\": 60,\\n          \\"brotli\\": 50\\n        },\\n        \\"all\\": {\\n          \\"raw\\": -99900,\\n          \\"gzip\\": -9940,\\n          \\"brotli\\": -9950\\n        }\\n      }\\n    }\\n  }\\n}\\n",
 "reportOut": "Wrote ROOT/.build/performance/report.json\\nWrote ROOT/.build/performance/report.md",
 "reportMd": "# SwiftUIWeb performance contract report\\n\\nGenerated: T\\n\\n| Budget | Measured | Baseline | Limit | Delta to limit | Source |\\n| --- | ---: | ---: | ---: | ---: | --- |\\n| initial-brotli-wasm | 700000.000 | 710000.000 | 650000 | -50000.000 | artifact-size |\\n| artifact-regression | 1000060.000 | 1010000.000 | 1100000 | 99940.000 | artifact-size |\\n| list-startup | 105.500 | — | 200 | 94.500 | browser |\\n| list-dom-mutations | 5.000 | — | 12 | 7.000 | browser |\\n| embedded-startup | 250.000 | — | 1000 | 750.000 | browser |\\n| released-render-nodes | 0.000 | — | 0 | 0.000 | swift-memory |\\n| list-10000-peak | 2000000.000 | — | 3000000 | 1000000.000 | swift-memory |\\n\\n## Before/after deltas\\n\\nThe JSON report contains \`baseline\` and \`deltas\` for artifact metrics. A dash in the table means that a metric has no checked-in historical baseline; its budget is still enforced.\\n\\nThe checked-in budget is the contract; this report is diagnostic and is never written back as a baseline.\\n",
 "checkOut": "REPORT initial-brotli-wasm: 700000 bytes, target 650000 (above target), baseline 710000 (-1.41%)\\nPASS performance contracts (6 budgets, scope=all)"
}`);

  await test("the Swift benchmark uses the serial Swift Testing runner", () =>
    withTemporary((directory) => {
      fixtureRoot(directory);
      const captured = [];
      const ctx = cannedContext(directory);
      const run = ctx.run;
      ctx.run = (command, output) => {
        captured.push(command);
        return run(command, output);
      };
      collectSwift(ctx);
      const command = captured[0];
      for (const flag of ["--enable-swift-testing", "--disable-xctest", "--no-parallel", "--disable-sandbox", "-debug-info-format", "none"]) assert.ok(command.includes(flag), flag);
      assert.ok(command.includes("MemoryBenchmarks"));
    }));

  await test("a stale artifact never satisfies the Showcase contract", () =>
    withTemporary((directory) => {
      fixtureRoot(directory, { browserBuild: false });
      write(join(directory, ".build/performance/artifact-size.json"), { artifacts: [{ name: "HelloWorld", status: "ready", analysis: { totals: {} } }] });
      const ctx = cannedContext(directory);
      const report = mergeReport(ctx);
      assert.equal(report.provenance.artifact, "checked-in-baseline");
      assert.ok("ShowcaseApp" in report.artifacts);
      assert.ok(!("HelloWorld" in report.artifacts));
    }));

  await test("an artifact regression against the baseline is a failed gate", () =>
    withTemporary((directory) => {
      const budgets = join(directory, "budgets.json");
      writeFileSync(budgets, JSON.stringify({ budgets: [{ name: "artifact", path: "artifacts.ShowcaseApp.initial.brotli", maxRegressionPercent: 5, source: "artifact-size", unit: "bytes" }] }));
      const report = { artifacts: { ShowcaseApp: { initial: { brotli: 106 } } }, baseline: { artifacts: { ShowcaseApp: { initial: { brotli: 100 } } } } };
      const lines = [];
      assert.throws(() => check({ budgets }, report, "browser", (line) => lines.push(line)), (error) => error instanceof ExitError && error.code === 1);
      assert.deepEqual(lines, ["FAIL artifact: 106 > baseline + 5.00% (105.000)"]);
    }));

  await test("a size above its target is reported and never fails", () =>
    withTemporary((directory) => {
      const budgets = join(directory, "budgets.json");
      writeFileSync(budgets, JSON.stringify({ budgets: [
        { name: "size", path: "artifacts.A.initial.brotli", max: 100, unit: "bytes", source: "artifact-size", enforcement: "report" },
        { name: "nothing", path: "artifacts.A.missing", unit: "bytes", source: "artifact-size", enforcement: "report" },
        { name: "count", path: "swift.n", max: 5, unit: "n", source: "swift" },
      ] }));
      const report = { artifacts: { A: { initial: { brotli: 110 } } }, swift: { n: 5 }, baseline: { artifacts: { A: { initial: { brotli: 100 } } } } };
      const lines = [];
      check({ budgets }, report, "all", (line) => lines.push(line));
      assert.deepEqual(lines, [
        "REPORT size: 110 bytes, target 100 (above target), baseline 100 (+10.00%)",
        "REPORT nothing: no measurement at artifacts.A.missing",
        "PASS performance contracts (1 budgets, scope=all)",
      ]);
      assert.throws(() => check({ budgets }, { swift: {} }, "browser", () => {}), (error) => error instanceof ExitError && /No browser performance metrics/.test(error.message));
    }));

  await test("key=value lines parse with int and float kept apart", () => {
    assert.equal(parseKv("no commas"), null);
    const [prefix, values] = parseKv("  list-scale,count=100,ratio=2.50,name=abc,flag,x=1e3,y=1.2.3,big=12  ");
    assert.equal(prefix, "list-scale");
    assert.equal(values.count, 100);
    assert.ok(values.ratio instanceof Float && Number(values.ratio) === 2.5);
    assert.equal(values.name, "abc");
    assert.ok(!("flag" in values));
    assert.equal(values.x, "1e3");
    assert.equal(values.y, "1.2.3");
    assert.equal(values.big, 12);
    assert.deepEqual(parseKv("only,"), ["only", {}]);
  });

  await test("dotted paths can contain dotted keys and numeric keys", () => {
    const report = { a: { "b.c": { d: 1 } }, listScale: { 10000: { peakBytes: 7 } } };
    assert.equal(getPath(report, "a.b.c.d"), 1);
    assert.equal(getPath(report, "listScale.10000.peakBytes"), 7);
    assert.equal(getPath(report, "a.missing"), null);
    assert.equal(getPath(report, ""), report);
  });

  await test("the Swift collector fails with a pointer to the log when a metric is missing", () =>
    withTemporary((directory) => {
      fixtureRoot(directory);
      const ctx = cannedContext(directory);
      ctx.run = () => "nothing useful";
      assert.throws(() => collectSwift(ctx), (error) => error instanceof ExitError && /did not publish required metrics; see .*swift-memory\.log/.test(error.message));
      ctx.run = () => { throw new ExitError("performance command failed (3): swift test"); };
      assert.throws(() => collectArtifact(ctx), (error) => error instanceof ExitError && error.code === 1);
    }));

  await test("the phases write the same files as the goldens, byte for byte", () =>
    withTemporary((directory) => {
      fixtureRoot(directory);
      const ctx = cannedContext(directory);
      const phases = (...argv) => capture(() => main(argv, ctx));
      let result = phases("--phase", "swift");
      assert.equal(result.thrown, null);
      assert.equal(result.out, GOLDEN.swiftOut);
      assert.equal(read(directory, "swift-metrics.json"), GOLDEN.swiftMetrics);
      assert.equal(mask(read(directory, "report.json")), GOLDEN.swiftReport);
      result = phases("--phase", "browser");
      assert.equal(result.out, GOLDEN.browserOut);
      assert.ok(result.thrown === null, String(result.thrown));
      assert.equal(read(directory, "artifact-size.json").replaceAll(directory, "ROOT"), GOLDEN.artifactSize);
      assert.equal(mask(read(directory, "report.json")), GOLDEN.browserReport);
      result = phases("--phase", "report");
      assert.equal(result.out.replaceAll(directory, "ROOT"), GOLDEN.reportOut);
      assert.equal(mask(read(directory, "report.md")), GOLDEN.reportMd);
      result = phases("--phase", "check", "--scope", "all");
      assert.equal(result.out, GOLDEN.checkOut);
    }));

  await test("an over-budget metric ends the check with status 1 and a FAIL line", () =>
    withTemporary((directory) => {
      fixtureRoot(directory);
      const ctx = cannedContext(directory);
      capture(() => main(["--phase", "swift"], ctx));
      const metrics = JSON.parse(read(directory, "swift-metrics.json"));
      metrics.release.renderNodeLive = 5;
      writeFileSync(join(directory, ".build/performance/swift-metrics.json"), JSON.stringify(metrics));
      const result = capture(() => main(["--phase", "check", "--scope", "swift"], ctx));
      assert.ok(result.thrown instanceof ExitError && result.thrown.code === 1);
      assert.match(result.out, /FAIL released-render-nodes: 5 > max 0 nodes/);
    }));

  await test("the command line rejects an unknown phase with status 2 and make targets run the Bun tool", () => {
    const bad = Bun.spawnSync(["bun", join(ROOT, "Tools/performance-contracts.mjs"), "--phase", "nope"], { stdout: "pipe", stderr: "pipe" });
    assert.equal(bad.exitCode, 2);
    assert.match(bad.stderr.toString(), /invalid choice: 'nope' \(choose from swift, memory, browser, report, check\)/);
    const none = Bun.spawnSync(["bun", join(ROOT, "Tools/performance-contracts.mjs")], { stdout: "pipe", stderr: "pipe" });
    assert.equal(none.exitCode, 2);
    for (const [target, phase] of [["perf-test", "swift"], ["memory-test", "memory"], ["perf-report", "report"], ["perf-ci", "check --scope all"]]) {
      const make = Bun.spawnSync(["make", "-n", target], { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
      assert.match(make.stdout.toString(), new RegExp(`bun Tools/performance-contracts\\.mjs --phase ${phase}`), target);
    }
  });

  finish();
}
