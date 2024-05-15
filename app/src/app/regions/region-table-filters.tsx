import { Dispatch, SetStateAction } from "react";
import TableSearchFilter from "../../components/table/table-text-search-filter";
import ResetFilterButton from "@/components/table/reset-filter-button";
export default function RegionTableFilters({
  setQueries,
  setPagination,
  queries,
}: {
  setQueries: Dispatch<
    SetStateAction<{
      name: string;
      code: string;
    }>
  >;
  setPagination: Dispatch<
    SetStateAction<{ pageSize: number; pageNumber: number }>
  >;
  queries: Record<string, string | null>;
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
      <TableSearchFilter
        onFilterChange={handleFilterChange}
        queries={queries}
        type="name"
      />
      <TableSearchFilter
        onFilterChange={handleFilterChange}
        queries={queries}
        type="code"
      />
      <ResetFilterButton onReset={handleResetFilter} />
    </div>
  );
}
