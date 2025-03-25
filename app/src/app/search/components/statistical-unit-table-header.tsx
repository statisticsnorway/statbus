import { TableHead, TableHeader, TableRow } from "@/components/ui/table";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import { useBaseData } from "@/app/BaseDataClient";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useTableColumns } from "../table-columns";

interface StatisticalUnitTableHeaderProps {
  regionLevel: number;
  setRegionLevel: (level: number) => void;
  maxRegionLevel: number;
}

export function StatisticalUnitTableHeader({
  regionLevel,
  setRegionLevel,
  maxRegionLevel,
}: StatisticalUnitTableHeaderProps) {
  const { statDefinitions, externalIdentTypes } = useBaseData();
  const { visibleColumns, headerRowSuffix, headerCellSuffix } =
    useTableColumns();

  return (
    <TableHeader className="bg-gray-50">
      <TableRow key={`h-row-${headerRowSuffix}`}>
        {visibleColumns.map(column => {
          switch (column.code) {
            case "name":
              return (
                <SortableTableHead
                  name="name"
                  label="Name"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  <small className="flex">
                    {externalIdentTypes.map(({ name }) => name).join(" | ")}
                  </small>
                </SortableTableHead>
              );
            case "activity_section":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Activity Section
                </TableHead>
              );
            case "top_region":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Top Region
                </TableHead>
              );
            case "region":
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell *:align-middle"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="physical_region_path"
                  label="Region"
                >
                  <small className="flex items-center whitespace-nowrap">
                    <Button
                      variant="ghost"
                      disabled={regionLevel === 1}
                      onClick={() => setRegionLevel(regionLevel - 1)}
                      className="h-4 w-4"
                      size="icon"
                    >
                      <ChevronLeft />
                    </Button>
                    <span title="Region level">Level {regionLevel}</span>
                    <Button
                      variant="ghost"
                      disabled={regionLevel === maxRegionLevel}
                      onClick={() => setRegionLevel(regionLevel + 1)}
                      className="h-4 w-4"
                      size="icon"
                    >
                      <ChevronRight />
                    </Button>
                  </small>
                </SortableTableHead>
              );
            case "statistic":
              if (column.type === "Adaptable" && column.stat_code) {
                // Retrieve the matching stat definition based on stat_code
                const statDefinition = statDefinitions.find(
                  (statDefinition) => statDefinition.code === column.stat_code
                );

                return (
                  statDefinition && (
                    <SortableTableHead
                      key={`h-cell-${headerCellSuffix(column)}`}
                      className="text-right hidden lg:table-cell *:capitalize"
                      name={statDefinition.code!}
                      label={statDefinition.name!}
                    />
                  )
                );
              }
            case "unit_counts":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Unit Counts
                </TableHead>
              );

            case "sector":
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="sector_path"
                  label="Sector"
                />
              );
            case "legal_form":
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="legal_form_code"
                  label="Legal Form"
                />
              );
            case "activity":
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="primary_activity_category_path"
                  label="Activity Category"
                />
              );
            case "secondary_activity":
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="secondary_activity_category_path"
                  label="Secondary Activity"
                />
              );
            case "physical_address":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Address
                </TableHead>
              );
            case "birth_date":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Birth Date
                </TableHead>
              );
            case "death_date":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Death Date
                </TableHead>
              );
            case "status":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Status
                </TableHead>
              );
            case "unit_size":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Unit Size
                </TableHead>
              );
            case "data_sources":
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >
                  Data Sources
                </TableHead>
              );
            case "last_edit":
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="last_edit_at"
                  label="Last Edit"
                />
              );
          }
        })}
        <TableHead />
      </TableRow>
    </TableHeader>
  );
}
