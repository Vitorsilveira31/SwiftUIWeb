// Shared by Tools/first-paint.mjs (capture and verify), Tools/first-paint-measure.mjs and the first-paint browser test.
import { createServer } from "node:net";

/** The first free port in `from`..`to` on the loopback interface (the tools default to 8180-8199). */
export async function claimPort(from = 8180, to = 8199) {
  for (let port = from; port <= to; port++) {
    const free = await new Promise((done) => {
      const probe = createServer();
      probe.once("error", () => done(false));
      probe.listen(port, "127.0.0.1", () => probe.close(() => done(true)));
    });
    if (free) return port;
  }
  throw new Error(`no free port in ${from}-${to}`);
}

/**
 * Compares two PNG screenshots pixel by pixel in a blank page of `browser` (no image library). Returns the size, the
 * number of pixels whose channels differ by more than `tolerance` (0 to 255), the largest channel difference and the
 * bounding box of the differing pixels.
 */
export async function compareScreenshots(browser, a, b, { tolerance = 0 } = {}) {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    await page.goto("about:blank");
    return await page.evaluate(async ({ a, b, tolerance }) => {
      const decode = async (base64) => {
        const image = new Image();
        image.src = `data:image/png;base64,${base64}`;
        await image.decode();
        const canvas = document.createElement("canvas");
        canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
        const context2d = canvas.getContext("2d", { willReadFrequently: true });
        context2d.drawImage(image, 0, 0);
        return context2d.getImageData(0, 0, canvas.width, canvas.height);
      };
      const [left, right] = [await decode(a), await decode(b)];
      if (left.width !== right.width || left.height !== right.height) return { sameSize: false, left: [left.width, left.height], right: [right.width, right.height], different: -1, maxDelta: 255, box: null };
      let different = 0, maxDelta = 0, x0 = left.width, y0 = left.height, x1 = -1, y1 = -1;
      for (let i = 0; i < left.data.length; i += 4) {
        let delta = 0;
        for (let c = 0; c < 4; c++) delta = Math.max(delta, Math.abs(left.data[i + c] - right.data[i + c]));
        if (delta > tolerance) {
          different++;
          const p = i / 4, x = p % left.width, y = (p - x) / left.width;
          if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
        if (delta > maxDelta) maxDelta = delta;
      }
      return { sameSize: true, width: left.width, height: left.height, different, maxDelta, box: different ? [x0, y0, x1, y1] : null };
    }, { a: a.toString("base64"), b: b.toString("base64"), tolerance });
  } finally {
    await context.close();
  }
}
