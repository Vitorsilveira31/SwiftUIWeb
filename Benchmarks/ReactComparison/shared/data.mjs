// The data both boards show, generated the same way in JavaScript (here) and in Swift
// (Tests/Apps/BoardBenchmarkApp/BoardData.swift), so the two apps answer every search with the same rows.
//
// A linear congruential generator makes it reproducible: each step is `state = (state * 1103515245 + 12345) mod 2^31`
// (a 32-bit multiply that wraps). Work `i` takes three steps: the adjective, the noun and the status.

export const WORK_COUNT = 2000;
export const ADJECTIVES = ["Quiet", "Golden", "Broken", "Silent", "Crimson", "Hidden", "Last", "Lost", "Bright", "Paper", "Midnight", "Iron", "Velvet", "Distant", "Hollow", "Savage"];
export const NOUNS = ["Harbor", "Garden", "Ledger", "Mirror", "Season", "Island", "Letter", "Engine", "Thread", "Winter", "Signal", "Orchard", "Empire", "Lantern", "Compass", "Archive"];
export const STATUSES = ["Draft", "Review", "Approved", "Released"];

export function makeWorks(count = WORK_COUNT) {
  let state = 1234567;
  const next = () => {
    state = (Math.imul(state, 1103515245) + 12345) & 0x7fffffff;
    return state;
  };
  const works = [];
  for (let index = 0; index < count; index += 1) {
    const adjective = ADJECTIVES[next() % ADJECTIVES.length];
    const noun = NOUNS[next() % NOUNS.length];
    const status = STATUSES[next() % STATUSES.length];
    works.push({ id: index + 1, title: `${adjective} ${noun} ${index + 1}`, status });
  }
  return works;
}

/** The search of both apps: a case-insensitive substring of the title. */
export function matches(work, query) {
  return query === "" || work.title.toLowerCase().includes(query.toLowerCase());
}

/** The cells of the stats view: a 20 by 10 grid whose numbers depend on how many works there are. */
export function statsCell(row, column, workCount) {
  return (row * 31 + column * 17 + workCount) % 97;
}
