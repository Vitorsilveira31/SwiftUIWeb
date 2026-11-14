import { useState } from "react";

// A long list written by hand, with no library: every row is the same height, so the row at a scroll position is a division, and
// only the rows in the viewport plus a margin of OVERSCAN rows on each side are rendered. A spacer as tall as the whole list gives
// the scrollbar its real length. The viewport height is the list's CSS height (600px in style.css).
export const ROW_HEIGHT = 44;
const VIEWPORT = 600;
const OVERSCAN = 20;

export function VirtualRows({ items, renderRow }) {
  const [scrollTop, setScrollTop] = useState(0);
  const first = Math.max(0, Math.floor(scrollTop / ROW_HEIGHT) - OVERSCAN);
  const last = Math.min(items.length, Math.ceil((scrollTop + VIEWPORT) / ROW_HEIGHT) + OVERSCAN);
  return (
    <div className="list" data-testid="list" onScroll={(event) => setScrollTop(event.currentTarget.scrollTop)}>
      <div style={{ position: "relative", height: items.length * ROW_HEIGHT }}>
        {items.slice(first, last).map((item, offset) => (
          <div key={item.id} style={{ position: "absolute", top: (first + offset) * ROW_HEIGHT, left: 0, right: 0 }}>
            {renderRow(item)}
          </div>
        ))}
      </div>
    </div>
  );
}
