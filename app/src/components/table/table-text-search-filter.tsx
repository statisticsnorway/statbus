import { QueryKeys } from "@/app/activity-categories/use-activity-categories";
import { Input } from "@/components/ui/input";
const TableTextSearchFilter = ({
  onFilterChange,
  value,
  type,
}: {
  onFilterChange: (filterName: string, value: string) => void;
  value: string | null;
  type: QueryKeys;
}) => {
  return (
    <Input
      name={`filter-${type}`}
      type="text"
      placeholder={`Filter by ${type}`}
      className="h-9 w-full md:max-w-[200px]"
      value={value ?? ""}
      onChange={(e) => onFilterChange(type, e.target.value)}
    />
  );
};
export default TableTextSearchFilter;
