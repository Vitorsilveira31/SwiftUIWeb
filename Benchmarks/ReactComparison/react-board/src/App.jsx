import { useCallback, useMemo, useState } from "react";
import { makeWorks, matches } from "../../shared/data.mjs";
import { Row } from "./Row.jsx";
import { StatsView } from "./StatsView.jsx";
import { VirtualRows } from "./VirtualRows.jsx";

// `?virtual=1` renders the same board with only the rows in view in the DOM (VirtualRows.jsx). Without it, every matching row is
// rendered, the way the plain React side is written.
const virtual = new URLSearchParams(window.location.search).get("virtual") === "1";

export function App() {
  const [works, setWorks] = useState(() => makeWorks());
  const [query, setQuery] = useState("");
  const [favorites, setFavorites] = useState(() => new Set());
  const [selectedId, setSelectedId] = useState(null);
  const [view, setView] = useState("board");
  const [added, setAdded] = useState(0);

  const visible = useMemo(() => works.filter((work) => matches(work, query)), [works, query]);
  const selected = works.find((work) => work.id === selectedId);

  const toggleFavorite = useCallback((id) => {
    setFavorites((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const addWork = () => {
    const count = added + 1;
    setAdded(count);
    setWorks((current) => [{ id: 2000 + count, title: `New work ${count}`, status: "Draft" }, ...current]);
  };

  const renderRow = (work) => (
    <Row key={work.id} work={work} isFavorite={favorites.has(work.id)} isSelected={work.id === selectedId} onToggleFavorite={toggleFavorite} onSelect={setSelectedId} />
  );

  return (
    <div className="app">
      <header>
        <h1>Works board</h1>
        <nav>
          <button type="button" data-testid="view-board" aria-pressed={view === "board"} onClick={() => setView("board")}>Board</button>
          <button type="button" data-testid="view-stats" aria-pressed={view === "stats"} onClick={() => setView("stats")}>Stats</button>
        </nav>
      </header>
      {view === "stats" ? (
        <StatsView workCount={works.length} />
      ) : (
        <main>
          <div className="toolbar">
            <input data-testid="search" type="search" placeholder="Search works" value={query} onChange={(event) => setQuery(event.target.value)} />
            <button type="button" data-testid="add-button" onClick={addWork}>Add work</button>
            <span data-testid="result-count">{visible.length} results</span>
            <span data-testid="fav-count">{favorites.size} favorites</span>
          </div>
          <div className="split">
            {virtual ? (
              <VirtualRows items={visible} renderRow={(work) => renderRow(work)} />
            ) : (
              <div className="list" data-testid="list">
                {visible.map((work) => renderRow(work))}
              </div>
            )}
            <aside className="detail">
              {selected ? <h2 data-testid="detail-title">{selected.title}</h2> : <p>Select a work</p>}
              {selected ? <p>{selected.status}</p> : null}
            </aside>
          </div>
        </main>
      )}
    </div>
  );
}
