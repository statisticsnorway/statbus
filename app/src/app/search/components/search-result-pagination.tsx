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

import { useSearchResult, useSearchPagination } from "@/atoms/search";

export default function SearchResultPagination() {
  const searchResult = useSearchResult();
  const { pagination, updatePagination } = useSearchPagination();
  const totalResults = searchResult?.total || 0;
  const totalPages = Math.ceil(totalResults / pagination.pageSize);

  const handlePageChange = (newPage: number) => {
    updatePagination(newPage);
  };

  if (!totalResults) return null;

  return (
    <Pagination>
      <PaginationContent>
        <PaginationItem>
          <PaginationFirst
            size="default"
            disabled={pagination.page == 1}
            onClick={() => handlePageChange(1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationPrevious
            size="default"
            disabled={pagination.page == 1}
            onClick={() => handlePageChange(pagination.page - 1)}
          />
        </PaginationItem>
        <li className="mx-2">
          Page {pagination.page} of {totalPages}
        </li>
        <PaginationItem>
          <PaginationNext
            size="default"
            disabled={pagination.page == totalPages}
            onClick={() => handlePageChange(pagination.page + 1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationLast
            size="default"
            disabled={pagination.page == totalPages}
            onClick={() => handlePageChange(totalPages)}
          />
        </PaginationItem>
      </PaginationContent>
    </Pagination>
  );
}
