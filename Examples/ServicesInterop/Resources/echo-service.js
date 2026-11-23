// A page service for Swift's `BrowserService("echo")`, defined before the framework starts (the registry adopts the queue).
(globalThis.SwiftUIWebServices ??= { queue: [], define(name, factory) { this.queue.push([name, factory]); } })
  .define("echo", ({ emit }) => ({
    greet: (name) => `Hello, ${name}`,
    start() {
      let count = 0;
      const timer = setInterval(() => { count += 1; emit("tick", String(count)); if (count === 3) clearInterval(timer); }, 50);
    },
    fail() { throw new Error("the echo service refused"); },
  }));
