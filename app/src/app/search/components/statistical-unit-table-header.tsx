import { TableHead, TableHeader, TableRow } from "@/components/ui/table";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import { useCustomConfigContext } from "@/app/use-custom-config-context";

export const StatisticalUnitTableHeader = () => {
  const { statDefinitions } = useCustomConfigContext();
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
        <SortableTableHead
          className="text-right hidden lg:table-cell [&>*]:capitalize"
          name={statDefinitions?.[0]?.code}
        >
          {statDefinitions?.[0]?.code}
        </SortableTableHead>
        <SortableTableHead
          className="text-right hidden lg:table-cell [&>*]:capitalize"
          name={statDefinitions?.[1]?.code}
        >
          {statDefinitions?.[1]?.code}
        </SortableTableHead>
        <SortableTableHead
          className="text-left hidden lg:table-cell"
          name="sector_code"
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
