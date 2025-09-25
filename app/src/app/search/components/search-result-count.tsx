"use client";
import { cn } from "@/lib/utils";
import { useSearchResult, useSearchPaginationValue } from '@/atoms/search';

export const SearchResultCount = ({
  className,
}: {
  readonly className?: string;
}) => {
  const searchResult = useSearchResult();
  const pagination = useSearchPaginationValue();

  const hasResults = searchResult?.total;
  const startIndex = hasResults
    ? (pagination.page - 1) * pagination.pageSize + 1
    : 0;
  const endIndex = hasResults
    ? Math.min(pagination.page * pagination.pageSize, searchResult.total)
    : 0;
  return (
    <span className={cn("indent-2.5", className)}>
      Showing {startIndex}-{endIndex} of total {searchResult?.total} results
    </span>
  );
};
