// The data of the mock API: the same resources, fields and counts as jsonplaceholder.typicode.com (10 users, 100 posts, 500
// comments, 100 albums, 5000 photos, 200 todos), made from a seed so every run is the same. The words are the project's own.
// A client written against this works against the real service, and the other way round.

/** A small deterministic generator (mulberry32). */
export function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const FIRST = ["Ana", "Bruno", "Carla", "Davi", "Elisa", "Fabio", "Gabi", "Hugo", "Iris", "Joel"];
const LAST = ["Alves", "Barros", "Campos", "Duarte", "Esteves", "Farias", "Gomes", "Horta", "Ibarra", "Junqueira"];
const CITIES = ["Lisbon", "Porto", "Recife", "Curitiba", "Valencia", "Ghent", "Tallinn", "Kraków", "Split", "Tbilisi"];
const STREETS = ["Harbor Lane", "Orchard Row", "Kite Street", "Lantern Court", "Mill Road", "Juniper Way", "Copper Alley", "Fern Hill", "Salt Quay", "Moss Terrace"];
const COMPANIES = ["Northwind Works", "Paper Kite", "Open Tide", "Lumen & Sons", "Cobalt Garden", "Slow Harvest", "Tin Whistle", "Blue Ledger", "Wild Thyme", "Quiet Engine"];
const NOUNS = ["morning", "harbor", "recipe", "trail", "workshop", "garden", "train", "market", "lighthouse", "notebook", "bakery", "river", "studio", "kitchen", "bridge", "ferry", "orchard", "library", "mountain", "cafe"];
const ADJECTIVES = ["quiet", "bright", "unexpected", "slow", "crowded", "tiny", "golden", "windy", "forgotten", "friendly", "restless", "honest", "sleepy", "wild", "careful"];
const VERBS = ["found", "rebuilt", "walked through", "photographed", "cooked", "mapped", "repaired", "shared", "followed", "tasted"];
const OPENERS = ["Today we", "Last weekend I", "Somebody once", "After the rain we", "On the way home I", "Early this morning we"];
const CLOSERS = ["and it was worth the detour.", "and nobody wanted to leave.", "and the light was perfect.", "and we will do it again.", "and it changed the plan for the week.", "and the coffee helped."];

const pick = (rand, list) => list[Math.floor(rand() * list.length)];
const sentence = (rand) => `${pick(rand, OPENERS)} ${pick(rand, VERBS)} the ${pick(rand, ADJECTIVES)} ${pick(rand, NOUNS)} ${pick(rand, CLOSERS)}`;
const title = (rand) => `The ${pick(rand, ADJECTIVES)} ${pick(rand, NOUNS)} ${pick(rand, VERBS).split(" ")[0]}`;
const paragraph = (rand, sentences) => Array.from({ length: sentences }, () => sentence(rand)).join("\n");
const slug = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, "");
const round = (value, places) => Number(value.toFixed(places));

export function makeData(seed = 20261028) {
  const rand = random(seed);
  const users = Array.from({ length: 10 }, (_, index) => {
    const first = FIRST[index], last = LAST[index], name = `${first} ${last}`;
    const username = `${first}${last}`.slice(0, 9);
    return {
      id: index + 1,
      name,
      username,
      email: `${slug(first)}.${slug(last)}@example.test`,
      address: {
        street: STREETS[index],
        suite: `Apt. ${Math.floor(rand() * 900) + 100}`,
        city: CITIES[index],
        zipcode: `${Math.floor(rand() * 90000) + 10000}`,
        geo: { lat: String(round(rand() * 120 - 60, 4)), lng: String(round(rand() * 300 - 150, 4)) },
      },
      phone: `+${Math.floor(rand() * 90) + 10} ${Math.floor(rand() * 900) + 100} ${Math.floor(rand() * 9000) + 1000}`,
      website: `${slug(first)}${slug(last)}.example.test`,
      company: { name: COMPANIES[index], catchPhrase: `${pick(rand, ADJECTIVES)} ${pick(rand, NOUNS)}s for everyone`, bs: `${pick(rand, VERBS)} ${pick(rand, NOUNS)}s` },
    };
  });
  // The authors take turns (the real service gives posts 1 to 10 to the same user), so a feed or an inbox does not read as one person.
  const posts = Array.from({ length: 100 }, (_, index) => ({ userId: (index % 10) + 1, id: index + 1, title: title(rand), body: paragraph(rand, 3) }));
  const comments = Array.from({ length: 500 }, (_, index) => {
    const author = users[Math.floor(rand() * users.length)];
    return { postId: Math.floor(index / 5) + 1, id: index + 1, name: sentence(rand).slice(0, 38), email: author.email, body: paragraph(rand, 2) };
  });
  const albums = Array.from({ length: 100 }, (_, index) => ({ userId: Math.floor(index / 10) + 1, id: index + 1, title: `${pick(rand, ADJECTIVES)} ${pick(rand, NOUNS)}s` }));
  const photos = Array.from({ length: 5000 }, (_, index) => ({
    albumId: Math.floor(index / 50) + 1,
    id: index + 1,
    title: `${pick(rand, ADJECTIVES)} ${pick(rand, NOUNS)} ${index + 1}`,
    url: `/images/photo/${index + 1}.svg`,
    thumbnailUrl: `/images/thumb/${index + 1}.svg`,
  }));
  const todos = Array.from({ length: 200 }, (_, index) => ({ userId: Math.floor(index / 20) + 1, id: index + 1, title: `${pick(rand, VERBS)} the ${pick(rand, NOUNS)}`, completed: rand() < 0.4 }));
  return { users, posts, comments, albums, photos, todos };
}

/** The nested routes of jsonplaceholder: `/posts/1/comments` is the comments whose `postId` is 1. */
export const NESTED = {
  posts: { comments: "postId" },
  albums: { photos: "albumId" },
  users: { albums: "userId", todos: "userId", posts: "userId" },
};
