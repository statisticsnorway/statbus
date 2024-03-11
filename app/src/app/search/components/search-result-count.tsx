import {useSearchContext} from "@/app/search/search-provider";

export const SearchResultCount = () => {
  const {search: {pagination}, searchResult} = useSearchContext()
  const hasResults = searchResult?.count
  const startIndex = hasResults ? (pagination.pageNumber - 1) * pagination.pageSize + 1 : 0
  const endIndex = hasResults ? Math.min(pagination.pageNumber * pagination.pageSize, searchResult.count) : 0;
  return (
    <span className="indent-2.5">
        Showing {startIndex}-{endIndex} of total {searchResult?.count} results
    </span>
  )
}
