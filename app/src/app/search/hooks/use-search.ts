import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(filters: SearchFilter[]) {
  const searchParams = filters
    .map(f => [f.name, generatePostgrestQuery(f)])
    .filter(([, query]) => !!query)
    .reduce((params, [name, query]) => {
      params.set(name!, query!);
      return params;
    }, new URLSearchParams());

  const search = useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false
  })

  return {search, searchParams}
}

export function generateFTSQuery(prompt: string = ""): string | null {
  const cleanedPrompt = prompt.trim().toLowerCase();
  const isNegated = (word: string) => new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt)
  const uniqueWordsInPrompt = new Set(cleanedPrompt.match(/\b\w+\b/g) ?? []);
  const tsQuery = [...uniqueWordsInPrompt]
    .map(word => isNegated(word) ? `!'${word}':*` : `'${word}':*`)
    .join(' & ');

  return tsQuery ? `fts(simple).${tsQuery}` : null;
}

const generatePostgrestQuery = (f: SearchFilter) => {
  if (f.type === 'conditional') {
    return f.condition && f.selected.length ? `${f.condition}.${f.selected[0]}` : null
  }

  switch (f.name) {
    case 'search':
      return generateFTSQuery(f.selected[0])
    case 'tax_reg_ident':
      return f.selected[0] ? `eq.${f.selected[0]}` : null
    case 'unit_type':
      return f.selected.length ? `in.(${f.selected.join(',')})` : null
    case 'physical_region_path':
      return f.selected.length ? `cd.${f.selected.join()}` : null
    case 'primary_activity_category_path':
      return f.selected.length ? `cd.${f.selected.join()}` : null
    default:
      return null
  }
}
