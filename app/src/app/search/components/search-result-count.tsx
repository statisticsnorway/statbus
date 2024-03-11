import {useSearchContext} from "@/app/search/search-provider";

export const SearchResultCount = () => {
  const {search: {page}, searchResult} = useSearchContext()
  const hasResults = searchResult?.count
  const startIndex = hasResults ? (page.value - 1) * page.size + 1 : 0
  const endIndex = hasResults ? Math.min(page.value * page.size, searchResult.count) : 0;
  return (
    <span className="indent-2.5">
        Showing {startIndex}-{endIndex} of total {searchResult?.count} results
    </span>
  )
}
