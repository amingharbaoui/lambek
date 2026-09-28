// Pregroup reduction, the same interval algorithm as the engine (Invoke-LambekReduction):
// x^l x -> 1 and x x^r -> 1, found as nested pairs, with as few types left over as possible

// "o^l" -> { base: "o", order: -1 }, "o^rr" -> { base: "o", order: 2 }
export function parseTypes(text) {
  return text
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((token) => {
      // "p*": a type the request does not say but its parameters supply (a second folder is the place)
      const implied = token.endsWith("*");
      const [base, marks = ""] = token.replace(/\*$/, "").split("^");
      const order = [...marks].reduce((sum, mark) => sum + (mark === "r" ? 1 : mark === "l" ? -1 : 0), 0);
      return { base, order, marks, implied };
    });
}

// A supplied type goes where the type waiting for it can reach: after a loose x^l, before a loose x^r or x
export function placeImplied(types) {
  const said = types.filter((type) => !type.implied);
  const { leftover } = reduce(said);
  const loose = leftover.map((index) => said[index]);
  const list = [...said];
  for (const type of types.filter((item) => item.implied)) {
    if (loose.some((other) => other.base === type.base && other.order < 0)) list.push(type);
    else list.unshift(type);
  }
  return list;
}

export function reduce(types) {
  const n = types.length;
  const cost = Array.from({ length: n + 1 }, () => new Array(n + 1).fill(0));
  const choice = Array.from({ length: n + 1 }, () => new Array(n + 1).fill(-1));
  const costOf = (from, to) => (from > to ? 0 : cost[from][to]);

  for (let length = 1; length <= n; length++) {
    for (let i = 0; i + length - 1 < n; i++) {
      const j = i + length - 1;
      let best = 1 + costOf(i + 1, j);
      let bestChoice = -1;
      for (let m = i + 1; m <= j; m++) {
        const cancels = types[i].base === types[m].base && types[m].order === types[i].order + 1;
        if (cancels && costOf(i + 1, m - 1) === 0) {
          const candidate = costOf(m + 1, j);
          if (candidate < best) {
            best = candidate;
            bestChoice = m;
          }
        }
      }
      cost[i][j] = best;
      choice[i][j] = bestChoice;
    }
  }

  // Rebuild the pairs
  const pairs = [];
  const leftover = [];
  const ranges = [[0, n - 1]];
  while (ranges.length > 0) {
    const [i, j] = ranges.pop();
    if (i > j) continue;
    const m = choice[i][j];
    if (m === -1) {
      leftover.push(i);
      ranges.push([i + 1, j]);
    } else {
      pairs.push([i, m]);
      ranges.push([m + 1, j]);
      ranges.push([i + 1, m - 1]);
    }
  }
  return { pairs: pairs.sort((a, b) => a[0] - b[0]), leftover: leftover.sort((a, b) => a - b) };
}
