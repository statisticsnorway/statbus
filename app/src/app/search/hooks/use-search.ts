import useSWR, { Fetcher } from "swr";

const fetcher: Fetcher<SearchResult, string> = (...args) =>
  fetch(...args).then((res) => res.json());

export default function useSearch(searchFilterState: SearchState) {
  const { filters, order, pagination } = searchFilterState;
  const searchParams = filters
    .map((f) => [f.name, generatePostgrestQuery(f)])
    .filter(([, query]) => !!query)
    .reduce((params, [name, query]) => {
      params.set(name!, query!);
      return params;
    }, new URLSearchParams());

  if (order.name && order.direction) {
    searchParams.set("order", `${order.name}.${order.direction}`);
  }

  if (pagination.pageNumber && pagination.pageSize) {
    const offset = (pagination.pageNumber - 1) * pagination.pageSize;
    searchParams.set("limit", `${pagination.pageSize}`);
    searchParams.set("offset", `${offset}`);
  }

  const search = useSWR<SearchResult>(`/api/search?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false,
  });

  return { search, searchParams };
}

let wordBoundaryRegex: RegExp;

try {
  /*
   *   (?<=^|\P{L}) is a positive lookbehind that asserts the position is at the start of the string ^ or after a non-letter \P{L}.
   *   [\p{L}\p{N}]+ matches one or more letters or numbers, including Unicode characters.
   *   (?=\P{L}|$) is a lookahead that asserts the position is at the end of the string $ or before a non-letter \P{L}.
   */
  wordBoundaryRegex = new RegExp(
    "(?<=^|\\P{L})[\\p{L}\\p{N}]+(?=\\P{L}|$)",
    "gu"
  );
} catch (e) {
  console.debug(
    "failed to create regex with unicode word boundaries, falling back to ascii word boundaries"
  );
  wordBoundaryRegex = /\b\w+\b/g;
}

export function generateFTSQuery(prompt: string | null): string | null {
  if (!prompt) return null;
  const cleanedPrompt = prompt.trim().toLowerCase();
  const isNegated = (word: string) =>
    new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt);
  const uniqueWordsInPrompt = new Set(
    cleanedPrompt.match(wordBoundaryRegex) ?? []
  );
  return [...uniqueWordsInPrompt]
    .map((word) => (isNegated(word) ? `!'${word}':*` : `'${word}':*`))
    .join(" & ");
}

const generatePostgrestQuery = ({ selected, name }: SearchFilter) => {
  if (selected.length === 1 && selected[0] === null) {
    return "is.null";
  }

  switch (name) {
    case "search": {
      const query = generateFTSQuery(selected[0]);
      return query ? `fts(simple).${query}` : null;
    }
    case "tax_reg_ident":
      return selected[0] ? `eq.${selected[0]}` : null;
    case "unit_type":
      return selected.length > 0 ? `in.(${selected.join(",")})` : null;
    case "physical_region_path":
      return selected[0] ? `cd.${selected[0]}` : null;
    case "primary_activity_category_path":
      return selected[0] ? `cd.${selected[0]}` : null;
    case "sector_code":
      return selected.length > 0 ? `in.(${selected.join(",")})` : null;
    case "legal_form_code":
      return selected.length > 0 ? `in.(${selected.join(",")})` : null;
    case "invalid_codes": {
      return selected[0] === "yes" ? "not.is.null" : "is.null";
    }
    default:
      return null;
  }
};
