import { Dispatch, SetStateAction } from "react";
import TableTextSearchFilter from "../../components/table/table-text-search-filter";
import ResetFilterButton from "@/components/table/reset-filter-button";

type RegionQueries = { name: string; code: string; coordinates: "" | "with" | "without" };

const COORDINATE_CHOICES: { value: RegionQueries["coordinates"]; label: string }[] = [
  { value: "", label: "All" },
  { value: "with", label: "With coordinates" },
  { value: "without", label: "Without coordinates" },
];

export default function RegionTableFilters({
  setQueries,
  setPagination,
  queries,
}: {
  readonly setQueries: Dispatch<SetStateAction<RegionQueries>>;
  readonly setPagination: Dispatch<
    SetStateAction<{ pageSize: number; pageNumber: number }>
  >;
  readonly queries: RegionQueries;
}) {
  const handleFilterChange = (filterName: string, value: string) => {
    setQueries((prev) => {
      return { ...prev, [filterName]: value };
    });
    setPagination((prev) => ({ ...prev, pageNumber: 1 }));
  };
  const handleResetFilter = () => {
    setQueries({ name: "", code: "", coordinates: "" });
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
      {/* All, with or without a centre point: the ones without are where an admin uses Place on map. */}
      <div className="inline-flex h-9 overflow-hidden rounded-md border text-sm" role="group" aria-label="Coordinates" data-regions-coordinates-filter="">
        {COORDINATE_CHOICES.map(({ value, label }) => (
          <button
            key={value || "all"}
            type="button"
            aria-pressed={queries.coordinates === value}
            className={`px-3 ${queries.coordinates === value ? "bg-gray-900 text-white" : "bg-white hover:bg-gray-50"}`}
            onClick={() => handleFilterChange("coordinates", value)}
            data-coordinates={value || "all"}
          >
            {label}
          </button>
        ))}
      </div>
      <ResetFilterButton onReset={handleResetFilter} />
    </div>
  );
}
