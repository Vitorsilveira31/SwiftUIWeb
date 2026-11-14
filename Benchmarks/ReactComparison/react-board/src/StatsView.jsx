import { statsCell } from "../../shared/data.mjs";

const ROWS = 20;
const COLUMNS = 10;

export function StatsView({ workCount }) {
  const cells = [];
  for (let row = 0; row < ROWS; row += 1) {
    for (let column = 0; column < COLUMNS; column += 1) {
      cells.push(
        <div key={`${row}-${column}`} data-testid="stats-cell" className="cell">
          {statsCell(row, column, workCount)}
        </div>,
      );
    }
  }
  return (
    <section>
      <h2 data-testid="stats-title">Stats</h2>
      <div data-testid="stats-grid" className="grid">{cells}</div>
    </section>
  );
}
