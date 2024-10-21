import { Dispatch, SetStateAction } from "react";
import TableTextSearchFilter from "../../components/table/table-text-search-filter";
import ResetFilterButton from "@/components/table/reset-filter-button";

export default function ActivityCategoryTableFilters({
  setQueries,
  setPagination,
  queries,
}: {
  readonly setQueries: Dispatch<
    SetStateAction<{
      name: string;
      code: string;
    }>
  >;
  readonly setPagination: Dispatch<
    SetStateAction<{ pageSize: number; pageNumber: number }>
  >;
  readonly queries: Record<string, string | null>;
}) {
  const handleFilterChange = (filterName: string, value: string) => {
    setQueries((prev) => {
      return { ...prev, [filterName]: value };
    });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  const handleResetFilter = () => {
    setQueries({ name: "", code: "" });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      <TableTextSearchFilter
        onFilterChange={handleFilterChange}
        queries={queries}
        type="code"
      />
      <TableTextSearchFilter
        onFilterChange={handleFilterChange}
        queries={queries}
        type="name"
      />

      <ResetFilterButton onReset={handleResetFilter} />
    </div>
  );
}
