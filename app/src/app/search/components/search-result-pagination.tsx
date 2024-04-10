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

import { useSearchContext } from "@/app/search/use-search-context";

export default function SearchResultPagination() {
  const {
    search: { pagination },
    dispatch,
    searchResult,
  } = useSearchContext();
  const totalResults = searchResult?.count || 0;
  const totalPages = Math.ceil(totalResults / pagination.pageSize);

  const handlePageChange = (newPage: number) => {
    dispatch({ type: "set_page", payload: { pageNumber: newPage } });
  };

  if (!totalResults) return null;

  return (
    <Pagination>
      <PaginationContent>
        <PaginationItem>
          <PaginationFirst
            disabled={pagination.pageNumber == 1}
            onClick={() => handlePageChange(1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationPrevious
            disabled={pagination.pageNumber == 1}
            onClick={() => handlePageChange(pagination.pageNumber - 1)}
          />
        </PaginationItem>
        <li className="mx-2">
          Page {pagination.pageNumber} of {totalPages}
        </li>
        <PaginationItem>
          <PaginationNext
            disabled={pagination.pageNumber == totalPages}
            onClick={() => handlePageChange(pagination.pageNumber + 1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationLast
            disabled={pagination.pageNumber == totalPages}
            onClick={() => handlePageChange(totalPages)}
          />
        </PaginationItem>
      </PaginationContent>
    </Pagination>
  );
}
