"use client";
import { cn } from "@/lib/utils";
import { useSearchContext } from "@/app/search/use-search-context";

export const SearchResultCount = ({
  className,
}: {
  readonly className?: string;
}) => {
  const {
    searchState: { pagination },
    searchResult,
  } = useSearchContext();
  const hasResults = searchResult?.count;
  const startIndex = hasResults
    ? (pagination.pageNumber - 1) * pagination.pageSize + 1
    : 0;
  const endIndex = hasResults
    ? Math.min(pagination.pageNumber * pagination.pageSize, searchResult.count)
    : 0;
  return (
    <span className={cn("indent-2.5", className)}>
      Showing {startIndex}-{endIndex} of total {searchResult?.count} results
    </span>
  );
};
