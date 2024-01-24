import useSWR, {Fetcher} from "swr";
import type {SearchFilter, SearchResult} from "@/app/search/search.types";

const fetcher: Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(filters: SearchFilter[], fallbackData: SearchResult) {

  const searchParams = new URLSearchParams()

  filters
    .filter(({selected}) => !!selected?.[0])
    .forEach(f => {
      searchParams.set(f.name, f.postgrestQuery(f))
    })

  return useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false,
    fallbackData
  })
}
