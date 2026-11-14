// Run with: bun test ./Tools/test-compare-react-orders.mjs
import { expect, test } from "bun:test";
import { ORDERS } from "./compare-react.mjs";

test("each side is first, second, third and last equally often over the orders", () => {
  for (let place = 0; place < 4; place += 1) {
    const counts = {};
    for (const order of ORDERS) counts[order[place]] = (counts[order[place]] ?? 0) + 1;
    expect(Object.values(counts)).toEqual([2, 2, 2, 2]);
  }
  for (const order of ORDERS) expect([...order].sort()).toEqual(["a", "b", "c", "d"]);
});
