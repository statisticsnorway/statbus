import useSWR, {Fetcher} from "swr";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(searchFilterState: SearchState) {
  const {filters, order, pagination} = searchFilterState
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

  if (pagination.pageNumber && pagination.pageSize) {
    const offset = (pagination.pageNumber - 1) * pagination.pageSize;
    searchParams.set('limit', `${pagination.pageSize}`);
    searchParams.set('offset', `${offset}`);
  }

  const search = useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false
  })

  return {search, searchParams}
}

let wordBoundaryRegex: RegExp

try {
  /*
   *   (?<=^|\P{L}) is a positive lookbehind that asserts the position is at the start of the string ^ or after a non-letter \P{L}.
   *   [\p{L}\p{N}]+ matches one or more letters or numbers, including Unicode characters.
   *   (?=\P{L}|$) is a lookahead that asserts the position is at the end of the string $ or before a non-letter \P{L}.
   */
  wordBoundaryRegex = new RegExp('(?<=^|\\P{L})[\\p{L}\\p{N}]+(?=\\P{L}|$)', 'gu')
} catch (e) {
  console.debug('failed to create regex with unicode word boundaries, falling back to ascii word boundaries')
  wordBoundaryRegex = /\b\w+\b/g
}

export function generateFTSQuery(prompt: string = ""): string | null {
  const cleanedPrompt = prompt.trim().toLowerCase();
  const isNegated = (word: string) => new RegExp(`\\-\\b(${word})\\b`).test(cleanedPrompt)
  const uniqueWordsInPrompt = new Set(cleanedPrompt.match(wordBoundaryRegex) ?? []);
  const tsQuery = [...uniqueWordsInPrompt]
    .map(word => isNegated(word) ? `!'${word}':*` : `'${word}':*`)
    .join(' & ');

  return tsQuery ? `fts(simple).${tsQuery}` : null;
}

const generatePostgrestQuery = ({name, type, selected, condition}: SearchFilter) => {
  if (selected.length === 1 && selected[0] === null) {
    return 'is.null'
  }

  if (type === 'conditional') {
    return condition && selected.length === 1 ? `${condition}.${selected[0]}` : null
  }

  switch (name) {
    case 'search':
      return selected[0] ? generateFTSQuery(selected[0]) : null
    case 'tax_reg_ident':
      return selected[0] ? `eq.${selected[0]}` : null
    case "sector_code":
    case 'unit_type':
      return selected.length > 0 ? `in.(${selected.join(',')})` : null
    case 'physical_region_path':
    case 'primary_activity_category_path':
      return selected.length > 0 ? `cd.${selected[0]}` : null
    default:
      return null
  }
}
