import { Dispatch, SetStateAction } from "react";
import TableTextSearchFilter from "../../components/table/table-text-search-filter";
import ResetFilterButton from "@/components/table/reset-filter-button";
import TableBoolSearchFilter from "@/components/table/table-bool-search-filter";
import { Queries } from "./use-activity-categories";

export default function ActivityCategoryTableFilters({
  setQueries,
  setPagination,
  queries,
}: {
  readonly setQueries: Dispatch<
    SetStateAction<Queries>
  >;
  readonly setPagination: Dispatch<
    SetStateAction<{ pageSize: number; pageNumber: number }>
  >;
  readonly queries: Queries;
}) {
  const handleFilterChange = (filterName: string, value: string | boolean | null) => {
    setQueries((prev) => {
      return { ...prev, [filterName]: value?.toString() };
    });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  const handleResetFilter = () => {
    setQueries({ name: "", code: "", custom: null });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 [&>*]:mb-2 [&>*]:mx-1 w-screen lg:w-full">
      <TableTextSearchFilter
        onFilterChange={handleFilterChange}
        value={queries.code}
        type="code"
      />
      <TableTextSearchFilter
        onFilterChange={handleFilterChange}
        value={queries.name}
        type="name"
      />
      <TableBoolSearchFilter
        onFilterChange={handleFilterChange}
        value={queries.custom}
        type="custom"
      />

      <ResetFilterButton onReset={handleResetFilter} />
    </div>
  );
}
