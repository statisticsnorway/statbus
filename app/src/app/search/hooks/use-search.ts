import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(filters: SearchFilter[]) {
    const searchParams = filters
        .map(f => [f.name, f.postgrestQuery(f)])
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
