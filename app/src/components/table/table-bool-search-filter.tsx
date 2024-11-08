import { useCallback } from "react";
import { OptionsFilter } from "@/app/search/components/options-filter";
import { QueryKeys } from "@/app/activity-categories/use-activity-categories";
import { SearchFilterOption } from "@/app/search/search";
const TableBoolSearchFilter = ({
  onFilterChange,
  value,
  type,
}: {
  onFilterChange: (filterName: string, value: string | boolean | null) => void;
  value: boolean | null;
  type: QueryKeys;
}) => {
  const update = useCallback(
    ({ value }: SearchFilterOption) => {
      onFilterChange(type, value);
    },
    [onFilterChange, type]
  );

  const reset = useCallback(() => {
    onFilterChange(type, null);
  }, [onFilterChange, type]);

  return (
    <OptionsFilter
      className="p-2 h-9 md:max-w-[200px] capitalize"
      title={`${type} filter`}
      options={[
        { label: "Any", value: null, humanReadableValue: "Any", className: "bg-gray-200" },
        { label: "☑", value: "true", humanReadableValue: "☑", className: "bg-green-200" },
        { label: "☐", value: "false", humanReadableValue: "☐", className: "bg-orange-200" },
      ]}
      selectedValues={value !== null ? [value?.toString()] : []}
      onReset={reset}
      onToggle={update}
    />
  );
};
export default TableBoolSearchFilter;
