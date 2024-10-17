import { Input } from "@/components/ui/input";
const TableTextSearchFilter = ({
  onFilterChange,
  queries,
  type,
}: {
  onFilterChange: (filterName: string, value: string) => void;
  queries: Record<string, string | null>;
  type: string;
}) => {
  return (
    <Input
      name={`filter-${type}`}
      type="text"
      placeholder={`Filter by ${type}`}
      className="h-9 w-full md:max-w-[200px]"
      value={queries[type] ?? ""}
      onChange={(e) => onFilterChange(type, e.target.value)}
    />
  );
};
export default TableTextSearchFilter;
