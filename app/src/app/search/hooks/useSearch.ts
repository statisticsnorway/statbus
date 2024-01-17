import useSWR, {SWRResponse} from "swr";
import {fetcher} from "@/app/search/hooks/fetcher";

export default function useSearch(prompt: string, searchFilter: SearchFilter, fallbackData: SearchResult): SWRResponse<SearchResult> {

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

  return useSWR(`/search/api?${searchParams}`, fetcher, {
    keepPreviousData: true,
    fallbackData,
    revalidateOnFocus: false
  })
}
