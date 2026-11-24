"use client";
import {
  Pagination,
  PaginationContent,
  PaginationItem,
  PaginationNext,
  PaginationPrevious,
  PaginationFirst,
  PaginationLast,
} from "@/components/ui/pagination";
import { Loader2 } from "lucide-react";

import { useSearchResult, useSearchPagination } from "@/atoms/search";

export default function SearchResultPagination() {
  const searchResult = useSearchResult();
  const { pagination, updatePagination } = useSearchPagination();
  
  const hasData = searchResult?.data?.length > 0;
  const hasTotal = searchResult?.total !== null && searchResult?.total !== undefined;
  const isCountLoading = searchResult?.countLoading;
  
  const totalResults = hasTotal ? searchResult.total! : 0;
  const totalPages = hasTotal ? Math.ceil(totalResults / pagination.pageSize) : 0;

  const handlePageChange = (newPage: number) => {
    updatePagination(newPage);
  };

  // Show pagination if we have data
  if (!hasData) return null;

  const canGoBack = pagination.page > 1;
  // When count is loading, allow forward if we got a full page (there's probably more)
  // When count is known, check against totalPages
  const canGoForward = isCountLoading 
    ? searchResult.data.length === pagination.pageSize
    : pagination.page < totalPages;

  return (
    <Pagination>
      <PaginationContent>
        <PaginationItem>
          <PaginationFirst
            size="default"
            disabled={!canGoBack}
            onClick={() => handlePageChange(1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationPrevious
            size="default"
            disabled={!canGoBack}
            onClick={() => handlePageChange(pagination.page - 1)}
          />
        </PaginationItem>
        <li className="mx-2">
          Page {pagination.page} of{" "}
          {isCountLoading ? (
            <span className="inline-flex items-center gap-1">
              <Loader2 className="h-3 w-3 animate-spin" />
            </span>
          ) : (
            totalPages.toLocaleString()
          )}
        </li>
        <PaginationItem>
          <PaginationNext
            size="default"
            disabled={!canGoForward}
            onClick={() => handlePageChange(pagination.page + 1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationLast
            size="default"
            disabled={isCountLoading || pagination.page === totalPages}
            onClick={() => handlePageChange(totalPages)}
          />
        </PaginationItem>
      </PaginationContent>
    </Pagination>
  );
}
