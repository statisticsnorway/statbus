import useSWR, {Fetcher, SWRResponse} from "swr";

const fetcher : Fetcher<SearchResult, string> = (...args) => fetch(...args).then(res => res.json())

export default function useSearch(prompt: string, searchFilter: SearchFilter, fallbackData: SearchResult) {

  const searchParams = new URLSearchParams()

  if (prompt) {
    searchParams.set('q', prompt)
  }

  if (searchFilter.selectedRegions.length) {
    searchParams.set('region_codes', searchFilter.selectedRegions.join(','))
  }

  if (searchFilter.selectedActivityCategories.length) {
    searchParams.set('activity_category_codes', searchFilter.selectedActivityCategories.join(','))
  }

  return useSWR<SearchResult>(`/search/api?${searchParams}`, fetcher, {
    keepPreviousData: true,
    revalidateOnFocus: false,
    fallbackData
  })
}
