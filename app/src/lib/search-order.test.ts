import { reverseOrder, reverseOrderTerm } from "./search-order";

// A page from the end of a search result is read in the reversed order and then reversed back,
// so the reversed order must list exactly the same rows in the opposite sequence. The check
// sorts sample rows the way PostgreSQL does for an order string and compares.
type Row = { v: number | null; id: number };

function sortLikePostgres(rows: Row[], order: string): Row[] {
  const terms = order.split(",").map((term) => {
    const parts = term.split(".");
    const directionIndex = parts.findIndex((part) => part === "asc" || part === "desc");
    const direction = parts[directionIndex];
    const nullsPart = parts.slice(directionIndex + 1).find((part) => part.startsWith("nulls"));
    const nullsFirst = nullsPart ? nullsPart === "nullsfirst" : direction === "desc";
    return { key: parts.slice(0, directionIndex).join(".") as keyof Row, desc: direction === "desc", nullsFirst };
  });
  return [...rows].sort((a, b) => {
    for (const { key, desc, nullsFirst } of terms) {
      const x = a[key];
      const y = b[key];
      if (x === y) continue;
      if (x === null) return nullsFirst ? -1 : 1;
      if (y === null) return nullsFirst ? 1 : -1;
      return (x < y ? -1 : 1) * (desc ? -1 : 1);
    }
    return 0;
  });
}

const rows: Row[] = [
  { v: 5, id: 1 }, { v: null, id: 2 }, { v: 30, id: 3 }, { v: 5, id: 4 }, { v: null, id: 5 }, { v: 100, id: 6 },
];

describe("reverseOrder", () => {
  it.each([
    "v.desc.nullslast,id.asc",
    "v.asc,id.asc",
    "v.desc,id.asc",
    "v.asc.nullsfirst,id.desc",
  ])("lists the rows of %s in exactly the opposite sequence", (order) => {
    const forward = sortLikePostgres(rows, order);
    const reversed = sortLikePostgres(rows, reverseOrder(order));
    expect(reversed.map((row) => row.id)).toEqual([...forward].reverse().map((row) => row.id));
  });

  it("moves units without a value from last to first when a descending sort is reversed", () => {
    expect(reverseOrderTerm("stats_summary->employees->sum.desc.nullslast")).toBe(
      "stats_summary->employees->sum.asc.nullsfirst",
    );
  });

  it("keeps a term without a direction", () => {
    expect(reverseOrderTerm("name")).toBe("name");
  });
});
