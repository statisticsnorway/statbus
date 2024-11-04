import { TableHead, TableHeader, TableRow } from "@/components/ui/table";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import { useBaseData } from "@/app/BaseDataClient";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { useTableColumns } from "../use-table-columns";
import { ColumnSelector } from "./column-selector";

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
  const { columns, visibleColumns, toggleColumn, resetColumns, isDefaultState , headerRowSuffix, headerCellSuffix} = useTableColumns();

  return (
    <TableHeader className="bg-gray-50">
      <TableRow key={`h-row-${headerRowSuffix}`}>
        {visibleColumns.map(column => {
          switch (column.code) {
            case 'name':
              return (
                <SortableTableHead name="name" label="Name" key={`h-cell-${headerCellSuffix(column)}`}>
                  <small className="flex">
                    {externalIdentTypes.map(({ code }) => code).join(" | ")}
                  </small>
                </SortableTableHead>
              );
            case 'region':
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell [&>*]:align-middle"
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
            case 'statistic':
              if (column.type === 'Adaptable' && column.stat_code) {
                // Retrieve the matching stat definition based on stat_code
                const statDefinition = statDefinitions.find(statDefinition => statDefinition.code === column.stat_code);

                return (statDefinition &&
                  <SortableTableHead
                    key={`h-cell-${headerCellSuffix(column)}`}
                    className="text-right hidden lg:table-cell [&>*]:capitalize"
                    name={statDefinition.code!}
                    label={statDefinition.code!}
                  />
                );
              }
            case 'sector':
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="sector_path"
                  label="Sector"
                />
              );
            case 'activity':
              return (
                <SortableTableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                  name="primary_activity_category_path"
                  label="Activity Category"
                />
              );
            case 'data_sources':
              return (
                <TableHead
                  className="text-left hidden lg:table-cell"
                  key={`h-cell-${headerCellSuffix(column)}`}
                >Data Sources
                </TableHead>
              );
          }
        })}
        <TableHead className="py-2 p-1 text-right hidden lg:table-cell" key="header-column-selector">
          <ColumnSelector
            columns={columns}
            onToggleColumn={toggleColumn}
            onReset={resetColumns}
            isDefaultState={isDefaultState}
          />
        </TableHead>
      </TableRow>
    </TableHeader>
  );
}
