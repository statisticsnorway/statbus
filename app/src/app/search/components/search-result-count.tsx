"use client";
import { cn } from "@/lib/utils";
import { useSearchResult, useSearchPaginationValue } from '@/atoms/search';
import { Loader2 } from "lucide-react";

export const SearchResultCount = ({
  className,
}: {
  readonly className?: string;
}) => {
  const searchResult = useSearchResult();
  const pagination = useSearchPaginationValue();

  const hasData = searchResult?.data?.length > 0;
  const hasTotal = searchResult?.total !== null && searchResult?.total !== undefined;
  const isCountLoading = searchResult?.countLoading;
  
  // Calculate start/end based on pagination
  const startIndex = hasData
    ? (pagination.page - 1) * pagination.pageSize + 1
    : 0;
  
  // For end index, use data length if count not available, otherwise use min of page end and total
  const endIndex = hasData
    ? hasTotal 
      ? Math.min(pagination.page * pagination.pageSize, searchResult.total!)
      : (pagination.page - 1) * pagination.pageSize + searchResult.data.length
    : 0;

  // Format total with thousand separators
  const formattedTotal = hasTotal 
    ? searchResult.total!.toLocaleString()
    : null;

  return (
    <span className={cn("indent-2.5", className)}>
      Showing {startIndex}-{endIndex} of total{" "}
      {isCountLoading ? (
        <span className="inline-flex items-center gap-1">
          <Loader2 className="h-3 w-3 animate-spin" />
          <span className="text-muted-foreground">counting...</span>
        </span>
      ) : formattedTotal !== null ? (
        formattedTotal
      ) : (
        <span className="text-muted-foreground">—</span>
      )}{" "}
      results
    </span>
  );
};
