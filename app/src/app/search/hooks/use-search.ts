import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";
import {generateFTSQuery} from "@/app/search/hooks/use-filter";

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

const generatePostgrestQuery = (f: SearchFilter) => {
  // TODO: generate type safe filter name type to ensure all branches are covered
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
    case 'conditional':
      return f.condition && f.selected.length ? `${f.condition}.${f.selected[0]}` : null
    default:
      return null
  }
}
