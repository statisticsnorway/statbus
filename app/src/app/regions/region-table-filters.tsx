import { Dispatch, SetStateAction } from "react";
import TableTextSearchFilter from "../../components/table/table-text-search-filter";
import ResetFilterButton from "@/components/table/reset-filter-button";
export default function RegionTableFilters({
  setQueries,
  setPagination,
  queries,
}: {
  readonly setQueries: Dispatch<
    SetStateAction<{
      name: string;
      code: string;
      noCoordinates?: boolean;
    }>
  >;
  readonly setPagination: Dispatch<
    SetStateAction<{ pageSize: number; pageNumber: number }>
  >;
  readonly queries: { name: string; code: string; noCoordinates?: boolean };
}) {
  const handleFilterChange = (filterName: string, value: string) => {
    setQueries((prev) => {
      return { ...prev, [filterName]: value };
    });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  const handleResetFilter = () => {
    setQueries({ name: "", code: "", noCoordinates: false });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 *:mb-2 *:mx-1 w-screen lg:w-full">
      <TableTextSearchFilter
        onFilterChange={handleFilterChange}
        value={queries["code"]}
        type="code"
      />
      <TableTextSearchFilter
        onFilterChange={handleFilterChange}
        value={queries["name"]}
        type="name"
      />
      <label className="flex items-center gap-2 text-sm" data-regions-no-coordinates="">
        <input
          type="checkbox"
          checked={!!queries.noCoordinates}
          onChange={(e) => {
            setQueries((prev) => ({ ...prev, noCoordinates: e.target.checked }));
            setPagination((prev) => ({ ...prev, pageNumber: 1 }));
          }}
        />
        Without coordinates
      </label>
      <ResetFilterButton onReset={handleResetFilter} />
    </div>
  );
}
