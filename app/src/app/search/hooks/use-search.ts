import useSWR, { Fetcher } from "swr";

import { useTimeContext } from "@/app/use-time-context";

const fetcher: Fetcher<SearchResult, string> = (...args) =>
  fetch(...args).then((res) => res.json());

export default function useSearch(searchFilterState: SearchState) {
  const { selectedPeriod } = useTimeContext();
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

  if (selectedPeriod) {
    searchParams.set("valid_from", `lte.${selectedPeriod.valid_on}`);
    searchParams.set("valid_to", `gte.${selectedPeriod.valid_on}`);
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

export function generateFTSQuery(prompt: string): string {
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

const generatePostgrestQuery = ({ selected, name, operator }: SearchFilter) => {
  if (!selected.some((value) => value != "")) return null;

  if (selected.length === 1 && selected[0] === null) {
    return "is.null";
  }

  switch (name) {
    case "search":
      return `fts(simple).${generateFTSQuery(selected[0]!!)}`;
    case "tax_ident":
      return `eq.${selected[0]}`;
    case "unit_type":
      return `in.(${selected.join(",")})`;
    case "physical_region_path":
      return `cd.${selected[0]}`;
    case "primary_activity_category_path":
      return `cd.${selected[0]}`;
    case "sector_code":
      return `in.(${selected.join(",")})`;
    case "legal_form_code":
      return `in.(${selected.join(",")})`;
    case "invalid_codes":
      return selected[0] === "yes" ? "not.is.null" : null;
    default:
      return `${operator ? `${operator}.` : ""}${selected.join(",")}`;
  }
};
