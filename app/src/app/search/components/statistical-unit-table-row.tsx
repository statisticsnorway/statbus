"use client";
import { TableColumn } from "../search.d";
import { TableCell, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { StatisticalUnitDetailsLink } from "@/components/statistical-unit-details-link";
import SearchResultTableRowDropdownMenu from "@/app/search/components/search-result-table-row-dropdown-menu";
import { useSelectionContext } from "@/app/search/use-selection-context";
import { useSearchContext } from "@/app/search/use-search-context";
import { thousandSeparator } from "@/lib/number-utils";
import { useBaseData } from "@/app/BaseDataClient";
import { StatisticalUnit } from "@/app/types";
import { InvalidCodes } from "./invalid-codes";
import { Popover, PopoverContent } from "@/components/ui/popover";
import { PopoverTrigger } from "@radix-ui/react-popover";
import { useTableColumns } from "../table-columns";

interface SearchResultTableRowProps {
  unit: StatisticalUnit;
  className?: string;
  regionLevel: number;
}

export const StatisticalUnitTableRow = ({
  unit,
  regionLevel,
}: SearchResultTableRowProps) => {
  const { allRegions, allActivityCategories, allDataSources } = useSearchContext();
  const { statDefinitions, externalIdentTypes } = useBaseData();
  const { selected } = useSelectionContext();
  const { columns, bodyRowSuffix, bodyCellSuffix } = useTableColumns();

  const isInBasket = selected.some(
    (s) => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type
  );

  const getRegionByPath = (physical_region_path: unknown) => {
    if (typeof physical_region_path !== "string") return undefined;
    const regionParts = physical_region_path.split(".");
    const selectedRegionPath = regionParts.slice(0, regionLevel).join(".");
    return allRegions.find(({ path }) => path === selectedRegionPath);
  };

  const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
    allActivityCategories.find(
      ({ path }) => path === primary_activity_category_path
    );

  const activityCategory = getActivityCategoryByPath(
    unit.primary_activity_category_path
  );

  const getDataSourcesByIds = (data_source_ids: number[] | null) => {
    if (!data_source_ids) return [];
    return data_source_ids
      .map((id) => allDataSources.find((ds) => ds.id === id));
  };

  const dataSources = getDataSourcesByIds(unit.data_source_ids ?? []);

  const region = getRegionByPath(unit.physical_region_path);

  const prettifyUnitType = (type: UnitType | null): string => {
    switch (type) {
      case "enterprise":
        return "Enterprise";
      case "enterprise_group":
        return "Enterprise Group";
      case "legal_unit":
        return "Legal Unit";
      case "establishment":
        return "Establishment";
      default:
        return "Unknown";
    }
  };

  const getCellClassName = (column: TableColumn) => {
    return cn(
      "py-2",
      // Adaptable columns are hidden on small screens
      column.type === 'Adaptable' && "hidden",
      // Show on large screens only if visible
      column.type === 'Adaptable' && column.visible && "lg:table-cell",
      // Add specific styling for statistic columns
      column.code === 'statistic' && "text-right"
    );
  };

  return (
    <TableRow key={`row-${bodyRowSuffix(unit)}`} className={cn("", isInBasket ? "bg-gray-100" : "")}>
      {columns.map(column => {
        if (column.type === 'Adaptable' && !column.visible) {
          return null;
        }
        switch (column.code) {
          case 'name':
            if (column.type !== 'Always') return null;
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  className="flex items-center space-x-3 leading-tight"
                  title={unit.name ?? ""}
                >
                  <StatisticalUnitIcon type={unit.unit_type} className="w-5" />
                  <div className="flex flex-1 flex-col space-y-0.5 max-w-56">
                    {unit.unit_type && unit.unit_id && unit.name ? (
                      <StatisticalUnitDetailsLink
                        className="overflow-hidden overflow-ellipsis whitespace-nowrap"
                        id={unit.unit_id}
                        type={unit.unit_type}
                      >
                        {unit.name}
                      </StatisticalUnitDetailsLink>
                    ) : (
                      <span className="font-medium">{unit.name}</span>
                    )}
                    <small className="text-gray-700 flex items-center space-x-1">
                      <span className="flex">
                        {externalIdentTypes
                          ?.map(({ code }) => unit.external_idents[code!] || "")
                          .join(" | ")}
                      </span>
                      {unit.invalid_codes && (
                        <>
                          <span>|</span>
                          <InvalidCodes
                            invalidCodes={JSON.stringify(unit.invalid_codes)}
                          />
                        </>
                      )}
                    </small>
                  </div>
                </div>
              </TableCell>
            );

          case 'activity_section':
            const activitySection = unit.primary_activity_category_path ? allActivityCategories.find(
              ({ path }) => path === (unit.primary_activity_category_path as string | null)?.split('.')?.[0]
            ) : undefined;
            return (
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{activitySection?.label}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap">
                    {activitySection?.name}
                  </small>
                </div>
              </TableCell>
            );

          case 'activity':
            return (
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{activityCategory?.code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-36">
                    {activityCategory?.name}
                  </small>
                </div>
              </TableCell>
            );

            case 'top_region':
              const topRegion = unit.physical_region_path ? allRegions.find(
                ({ path }) => path === (unit.physical_region_path as string | null)?.split('.')[0]
              ) : undefined;
              return (
                <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                  <div className="flex flex-col space-y-0.5 leading-tight">
                    <span>{topRegion?.code}</span>
                    <small className="text-gray-700 max-w-20 overflow-hidden overflow-ellipsis whitespace-nowrap">
                      {topRegion?.name}
                    </small>
                  </div>
                </TableCell>
              );

          case 'region':
            return (
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{region?.code}</span>
                  <small className="text-gray-700 max-w-20 overflow-hidden overflow-ellipsis whitespace-nowrap">
                    {region?.name}
                  </small>
                </div>
              </TableCell>
            );

          case 'statistic':
            if (column.type === 'Adaptable' && column.stat_code) {
              return (
                <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                  {thousandSeparator(unit.stats_summary[column.stat_code]?.sum)}
                </TableCell>
              );
            }
            return null;

          case 'unit_counts':
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex flex-col space-y-0.5 leading-tight whitespace-nowrap">
                  {unit.enterprise_count != null &&
                    unit.enterprise_count > 0 && (
                      <small className="text-gray-700">
                        Enterprises: {unit.enterprise_count}
                      </small>
                    )}
                  {unit.legal_unit_count != null &&
                    unit.legal_unit_count > 0 && (
                      <small className="text-gray-700">
                        Legal Units: {unit.legal_unit_count}
                      </small>
                    )}
                  {unit.establishment_count != null &&
                    unit.establishment_count > 0 && (
                      <small className="text-gray-700">
                        Establishments: {unit.establishment_count}
                      </small>
                    )}
                </div>
              </TableCell>
            );

          case 'sector':
            return (
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{unit.sector_code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-32">
                    {unit.sector_name}
                  </small>
                </div>
              </TableCell>
            );

          case 'data_sources':
            return (
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  {dataSources.map((ds) => (
                    <Popover key={`dataSource-${ds?.id}`}>
                      <PopoverTrigger asChild>
                        <span className="cursor-pointer" title={ds?.name}>
                          {ds?.code}
                        </span>
                      </PopoverTrigger>
                      <PopoverContent className="p-1.5 w-full">
                        <p className="text-xs">{ds?.name}</p>
                      </PopoverContent>
                    </Popover>
                  ))}
                </div>
              </TableCell>
            );
        }
      })}
      <TableCell
        key="column-action"
        className="py-2 p-1 text-right"
      >
        <SearchResultTableRowDropdownMenu unit={unit} />
      </TableCell>
    </TableRow>
  );
};
