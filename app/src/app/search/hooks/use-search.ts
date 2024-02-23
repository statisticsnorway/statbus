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
