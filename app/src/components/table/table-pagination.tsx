import {
  Pagination,
  PaginationContent,
  PaginationFirst,
  PaginationItem,
  PaginationLast,
  PaginationNext,
  PaginationPrevious,
} from "@/components/ui/pagination";
import React, { Dispatch, SetStateAction } from "react";
type TablePagination = {
  readonly pageSize: number;
  readonly pageNumber: number;
};
interface PaginationProps {
  pagination: TablePagination;
  setPagination: Dispatch<SetStateAction<TablePagination>>;
  total: number;
}
const TablePagination = ({
  pagination,
  setPagination,
  total,
}: PaginationProps) => {
  const { pageNumber, pageSize } = pagination;
  const totalPages = Math.ceil((total ?? 1) / pageSize);
  if (!total) return null;
  const handlePageChange = (pageNumber: number) => {
    setPagination((prev) => ({ ...prev, pageNumber }));
  };
  return (
    <Pagination>
      <PaginationContent>
        <PaginationItem>
          <PaginationFirst
            disabled={pageNumber == 1}
            onClick={() => handlePageChange(1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationPrevious
            disabled={pageNumber == 1}
            onClick={() => handlePageChange(pageNumber - 1)}
          />
        </PaginationItem>
        <li className="mx-2">
          Page {pageNumber} of {totalPages}
        </li>
        <PaginationItem>
          <PaginationNext
            disabled={pageNumber == totalPages}
            onClick={() => handlePageChange(pageNumber + 1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationLast
            disabled={pageNumber == totalPages}
            onClick={() => handlePageChange(totalPages)}
          />
        </PaginationItem>
      </PaginationContent>
    </Pagination>
  );
};
export default TablePagination;
