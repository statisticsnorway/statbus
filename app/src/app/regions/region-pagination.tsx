"use client";
import {
  Pagination,
  PaginationContent,
  PaginationFirst,
  PaginationItem,
  PaginationLast,
  PaginationNext,
  PaginationPrevious,
} from "@/components/ui/pagination";
import { useRegionContext } from "./use-region-context";

export default function RegionPagination() {
  const {
    regions: { pagination },
    dispatch,
    regionsResult,
  } = useRegionContext();

  const totalResults = regionsResult?.count || 0;
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
