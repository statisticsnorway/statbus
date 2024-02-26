import {useSearchContext} from "@/app/search/search-provider";

export const SearchResultCount = () => {
  const {searchResult} = useSearchContext()
  return (
    <span className="indent-2.5">
        Showing {searchResult?.statisticalUnits?.length} of total {searchResult?.count} results
    </span>
  )
}
