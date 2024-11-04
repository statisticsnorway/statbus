"use client";
import { Tables } from "@/lib/database.types";
import { TableColumn, TableColumnCode } from "../search.d";
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
import { useTableColumns } from "../use-table-columns";

interface SearchResultTableRowProps {
  unit: Tables<"statistical_unit">;
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

  const {
    unit_type,
    unit_id,
    valid_from,
    name,
    primary_activity_category_path,
    physical_region_path,
    external_idents,
    stats_summary,
    sector_name,
    sector_code,
    invalid_codes,
    data_source_ids,
  } = unit as StatisticalUnit;

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
    primary_activity_category_path
  );

  const getDataSourcesByIds = (data_source_ids: number[] | null) => {
    if (!data_source_ids) return [];
    return data_source_ids
      .map((id) => allDataSources.find((ds) => ds.id === id));
  };

  const dataSources = getDataSourcesByIds(data_source_ids ?? []);

  const region = getRegionByPath(physical_region_path);

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
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex items-center space-x-3 leading-tight" title={name ?? ""}>
                  <StatisticalUnitIcon type={unit_type} className="w-5" />
                  <div className="flex flex-1 flex-col space-y-0.5 max-w-56">
                    {unit_type && unit_id && name ? (
                      <StatisticalUnitDetailsLink
                        className="overflow-hidden overflow-ellipsis whitespace-nowrap"
                        id={unit_id}
                        type={unit_type}
                      >
                        {name}
                      </StatisticalUnitDetailsLink>
                    ) : (
                      <span className="font-medium">{name}</span>
                    )}
                    <small className="text-gray-700 flex items-center space-x-1">
                      <span className="flex">
                        {externalIdentTypes
                          ?.map(({ code }) => external_idents[code!] || "")
                          .join(" | ")}
                      </span>
                      {invalid_codes && (
                        <>
                          <span>|</span>
                          <InvalidCodes invalidCodes={JSON.stringify(invalid_codes)} />
                        </>
                      )}
                    </small>
                  </div>
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
                  {thousandSeparator(stats_summary[column.stat_code]?.sum)}
                </TableCell>
              );
            }
            return null;

          case 'sector':
            return (
              <TableCell key={`cell-${bodyCellSuffix(unit, column)}`} className={getCellClassName(column)}>
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span>{sector_code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-32">
                    {sector_name}
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
