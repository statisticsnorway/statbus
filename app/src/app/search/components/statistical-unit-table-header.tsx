import { TableHead, TableHeader, TableRow } from "@/components/ui/table";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import { useBaseData } from "@/app/BaseDataClient";

export const StatisticalUnitTableHeader = () => {
  const { statDefinitions } = useBaseData();

  return (
    <TableHeader className="bg-gray-50">
      <TableRow>
        <SortableTableHead name="name">Name</SortableTableHead>
        <SortableTableHead
          className="text-left hidden lg:table-cell"
          name="physical_region_path"
        >
          Region
        </SortableTableHead>
        {statDefinitions.map(({ code }) => (
          <SortableTableHead
            key={code}
            className="text-right hidden lg:table-cell [&>*]:capitalize"
            name={code!}
          >
            {code}
          </SortableTableHead>
        ))}
        <SortableTableHead
          className="text-left hidden lg:table-cell"
          name="sector_path"
        >
          Sector
        </SortableTableHead>
        <SortableTableHead
          className="text-left hidden lg:table-cell"
          name="primary_activity_category_path"
        >
          Activity Category
        </SortableTableHead>
        <TableHead />
      </TableRow>
    </TableHeader>
  );
};
