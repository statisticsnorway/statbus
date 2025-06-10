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

import { useSearch } from "@/atoms/hooks";

export default function SearchResultPagination() {
  const {
    searchState,
    searchResult,
    updatePagination,
    executeSearch,
  } = useSearch();
  const { pagination } = searchState;
  const totalResults = searchResult?.total || 0;
  const totalPages = Math.ceil(totalResults / pagination.pageSize);

  const handlePageChange = async (newPage: number) => {
    updatePagination(newPage);
    await executeSearch();
  };

  if (!totalResults) return null;

  return (
    <Pagination>
      <PaginationContent>
        <PaginationItem>
          <PaginationFirst
            disabled={pagination.page == 1}
            onClick={() => handlePageChange(1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationPrevious
            disabled={pagination.page == 1}
            onClick={() => handlePageChange(pagination.page - 1)}
          />
        </PaginationItem>
        <li className="mx-2">
          Page {pagination.page} of {totalPages}
        </li>
        <PaginationItem>
          <PaginationNext
            disabled={pagination.page == totalPages}
            onClick={() => handlePageChange(pagination.page + 1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationLast
            disabled={pagination.page == totalPages}
            onClick={() => handlePageChange(totalPages)}
          />
        </PaginationItem>
      </PaginationContent>
    </Pagination>
  );
}
