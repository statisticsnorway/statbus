import { Dispatch, SetStateAction } from "react";
import TableTextSearchFilter from "../../components/table/table-text-search-filter";
import ResetFilterButton from "@/components/table/reset-filter-button";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

type RegionQueries = { name: string; code: string; coordinates: "" | "with" | "without" };

/** "" is All; Radix Select gives no item an empty value, so All is "all" inside the dropdown. */
const COORDINATE_CHOICES: { value: "all" | "with" | "without"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "with", label: "With coordinates" },
  { value: "without", label: "Without coordinates" },
];

/**
 * The list's filters (owner 2026-11-26, 5yxn4w): code and name, Reset, then Advanced. Advanced on
 * shows the Coordinates column and a dropdown filter: all regions, those with a centre, or those
 * without one, which is where an admin edits one. Advanced off resets that filter, so no hidden
 * filter narrows the list.
 */
export default function RegionTableFilters({
  setQueries,
  setPagination,
  queries,
  advanced,
  setAdvanced,
}: {
  readonly setQueries: Dispatch<SetStateAction<RegionQueries>>;
  readonly setPagination: Dispatch<
    SetStateAction<{ pageSize: number; pageNumber: number }>
  >;
  readonly queries: RegionQueries;
  readonly advanced: boolean;
  readonly setAdvanced: (on: boolean) => void;
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
  const toggleAdvanced = (on: boolean) => {
    if (!on && queries.coordinates !== "") handleFilterChange("coordinates", "");
    setAdvanced(on);
  };
  return (
    <div className="flex flex-wrap items-center p-1 lg:p-0 *:mb-2 *:mx-1">
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
      {advanced && (
        <Select
          value={queries.coordinates || "all"}
          onValueChange={(v) => handleFilterChange("coordinates", v === "all" ? "" : v)}
        >
          <SelectTrigger className="h-9 w-52" aria-label="Coordinates" data-regions-coordinates-filter="">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {COORDINATE_CHOICES.map(({ value, label }) => (
              <SelectItem key={value} value={value} data-coordinates={value}>
                {label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
      <ResetFilterButton onReset={handleResetFilter} />
      <div className="flex h-9 items-center gap-2 px-1">
        <Label htmlFor="regions-advanced">Advanced</Label>
        <Switch
          id="regions-advanced"
          checked={advanced}
          onCheckedChange={toggleAdvanced}
          data-regions-advanced=""
        />
      </div>
    </div>
  );
}
