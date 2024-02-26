import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";
import {SearchOrder} from "@/app/search/search.types";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(filters: SearchFilter[], order: SearchOrder) {
  const searchParams = filters
    .map(f => [f.name, generatePostgrestQuery(f)])
    .filter(([, query]) => !!query)
    .reduce((params, [name, query]) => {
      params.set(name!, query!);
      return params;
    }, new URLSearchParams());

  if (order.name && order.direction) {
    searchParams.set('order', `${order.name}.${order.direction}`)
  }

  const search = useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false
  })

  return {search, searchParams}
}


/*
 *   (?<=^|\P{L}) is a positive lookbehind that asserts the position is at the start of the string ^ or after a non-letter \P{L}.
 *   [\p{L}\p{N}]+ matches one or more letters or numbers, including Unicode characters.
 *   (?=\P{L}|$) is a lookahead that asserts the position is at the end of the string $ or before a non-letter \P{L}.
 */
const unicodeWordBoundaryPattern = /(?<=^|\P{L})([\p{L}\p{N}]+)(?=\P{L}|$)/gu;

export function generateFTSQuery(prompt: string = ""): string | null {
  const cleanedPrompt = prompt.trim().toLowerCase();
  const isNegated = (word: string) => new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt)
  const uniqueWordsInPrompt = new Set(cleanedPrompt.match(unicodeWordBoundaryPattern) ?? []);
  const tsQuery = [...uniqueWordsInPrompt]
    .map(word => isNegated(word) ? `!'${word}':*` : `'${word}':*`)
    .join(' & ');

  return tsQuery ? `fts(simple).${tsQuery}` : null;
}

const generatePostgrestQuery = (f: SearchFilter) => {
  const {selected, type, name, condition} = f;

  if (type === 'conditional') {
    return condition && selected.length ? `${condition}.${selected[0]}` : null
  }

  switch (name) {
    case 'search':
      return selected[0] ? generateFTSQuery(selected[0]) : null
    case 'tax_reg_ident':
      return selected[0] ? `eq.${selected[0]}` : null
    case 'unit_type':
      return selected.length ? `in.(${selected.join(',')})` : null
    case 'physical_region_path':
    case 'primary_activity_category_path': {
      if (selected.length) {
        return selected[0] === null ? `is.null` : `cd.${selected[0]}`
      }
      return null
    }
    default:
      return null
  }
}
