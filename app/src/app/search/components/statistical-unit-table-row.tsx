"use client";
import { TableColumn } from "../search.d";
import { TableCell, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { StatisticalUnitDetailsLink } from "@/components/statistical-unit-details-link";
import SearchResultTableRowDropdownMenu from "@/app/search/components/search-result-table-row-dropdown-menu";
import { thousandSeparator } from "@/lib/number-utils";
import { Popover, PopoverContent } from "@/components/ui/popover";
import { PopoverTrigger } from "@radix-ui/react-popover";
import {
  useSelection,
  useTableColumnsManager,
  useSearchPageData,
  useSearchPageDataReady,
  StatisticalUnit,
} from "@/atoms/search";
import { statbusUsersAtom, externalIdentTypesAtom } from "@/atoms/base-data";
import { useAtomValue } from "jotai";
import { Tables } from "@/lib/database.types";
import { Square, SquareCheckBig } from "lucide-react";

interface SearchResultTableRowProps {
  unit: StatisticalUnit;
  className?: string;
  regionLevel: number;
}

export const StatisticalUnitTableRow = ({
  unit,
  regionLevel,
}: SearchResultTableRowProps) => {
  const {
    allRegions,
    allActivityCategories,
    allStatuses,
    allUnitSizes,
    allDataSources,
  } = useSearchPageData();
  const searchPageDataReady = useSearchPageDataReady();
  const externalIdentTypes = useAtomValue(externalIdentTypesAtom);
  const statbusUsers = useAtomValue(statbusUsersAtom);
  const { selected } = useSelection();
  const { columns, bodyRowSuffix, bodyCellSuffix } = useTableColumnsManager();

  const isInBasket = selected.some(
    (s: StatisticalUnit) => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type
  );

  const getRegionByPath = (physical_region_path: unknown) => {
    if (typeof physical_region_path !== "string") return undefined;
    const regionParts = physical_region_path.split(".");
    const selectedRegionPath = regionParts.slice(0, regionLevel).join(".");
    return allRegions.find(({ path }: Tables<'region_used'>) => path === selectedRegionPath);
  };

  const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
    allActivityCategories.find(
      ({ path }: Tables<'activity_category_used'>) => path === primary_activity_category_path
    );

  const activityCategory = getActivityCategoryByPath(
    unit.primary_activity_category_path
  );

  const secondaryActivityCategory = getActivityCategoryByPath(
    unit.secondary_activity_category_path
  );

  const getStatusById = (status_id: number | null) =>
    allStatuses.find(({ id }: Tables<'status'>) => id === status_id);

  const status = getStatusById(unit.status_id);

  const notUsedForCounting = status?.used_for_counting === false;

  const getUnitSizeById = (unit_size_id: number | null) =>
    allUnitSizes.find(({ id }: Tables<'unit_size'>) => id === unit_size_id);

  const unitSize = getUnitSizeById(unit.unit_size_id);

  const getDataSourcesByIds = (data_source_ids: number[] | null) => {
    if (!data_source_ids) return [];
    // Let TypeScript infer the type of `ds` to avoid mismatches.
    return data_source_ids.map((id) =>
      allDataSources.find(ds => ds.id === id)
    );
  };

  const dataSources = getDataSourcesByIds(unit.data_source_ids ?? []);

  const region = getRegionByPath(unit.physical_region_path);

  const physical_address = [
    unit.physical_address_part1,
    unit.physical_address_part2,
    unit.physical_address_part3,
  ]
    .filter(Boolean)
    .join(", ");

  const lastEditAt = new Date(unit.last_edit_at!);
  const formattedLastEditAt = `${lastEditAt.getFullYear()}-${String(lastEditAt.getMonth() + 1).padStart(2, "0")}-${String(
    lastEditAt.getDate()
  ).padStart(
    2,
    "0"
  )} ${String(lastEditAt.getHours()).padStart(2, "0")}:${String(lastEditAt.getMinutes()).padStart(2, "0")}`;

  const lastEditBy = statbusUsers
    .find((user: Tables<'user'>) => user.id === unit.last_edit_by_user_id)
    ?.display_name

  const getCellClassName = (column: TableColumn) => {
    return cn(
      "py-2",
      // Adaptable columns are hidden on small screens
      column.type === "Adaptable" && "hidden",
      // Show on large screens only if visible
      column.type === "Adaptable" && column.visible && "lg:table-cell",
      // Add specific styling for statistic columns
      column.code === "statistic" && "text-right"
    );
  };

  return (
    <TableRow
      key={`row-${bodyRowSuffix(unit)}`}
      className={cn(
        "",
        isInBasket ? "bg-gray-100" : "",
        notUsedForCounting && "italic text-gray-500"
      )}
      title={
        notUsedForCounting
          ? `This unit has status ${status.name} and is therefore not counted`
          : ""
      }
    >
      {columns.map((column: TableColumn) => {
        if (column.type === "Adaptable" && !column.visible) {
          return null;
        }
        switch (column.code) {
          case "name":
            if (column.type !== "Always") return null;
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex items-center space-x-3 leading-tight">
                  <StatisticalUnitIcon
                    type={unit.unit_type}
                    className="w-5"
                    hasLegalUnit={unit.has_legal_unit !== false}
                  />

                  <div className="flex flex-1 flex-col space-y-0.5 max-w-56">
                    {unit.unit_type && unit.unit_id && unit.name ? (
                      <StatisticalUnitDetailsLink
                        className="overflow-hidden text-ellipsis whitespace-nowrap"
                        id={unit.unit_id}
                        type={unit.unit_type}
                      >
                        {unit.name}
                      </StatisticalUnitDetailsLink>
                    ) : (
                      <span className="font-medium">{unit.name}</span>
                    )}
                    <small className="text-gray-700 flex items-center space-x-1">
                      <span className="flex text-wrap">
                        {externalIdentTypes
                          ?.map(
                            ({ code }: Tables<"external_ident_type_active">) =>
                              unit.external_idents[code!] || "-"
                          )
                          .join(" | ")}
                      </span>
                    </small>
                  </div>
                </div>
              </TableCell>
            );

          case "activity_section":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-6 bg-gray-200 rounded"></span>
                    <small className="h-3 w-24 bg-gray-100 rounded"></small>
                  </div>
                </TableCell>
              );
            }
            const activitySection = unit.primary_activity_category_path
              ? allActivityCategories.find(
                  ({ path }: Tables<'activity_category_used'>) =>
                    path ===
                    (
                      unit.primary_activity_category_path as string | null
                    )?.split(".")?.[0]
                )
              : undefined;
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={activitySection?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{activitySection?.label}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap">
                    {activitySection?.name}
                  </small>
                </div>
              </TableCell>
            );

          case "activity":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-12 bg-gray-200 rounded"></span>
                    <small className="h-3 w-28 bg-gray-100 rounded"></small>
                  </div>
                </TableCell>
              );
            }
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={activityCategory?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{activityCategory?.code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-36">
                    {activityCategory?.name}
                  </small>
                </div>
              </TableCell>
            );

          case "secondary_activity":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-12 bg-gray-200 rounded"></span>
                    <small className="h-3 w-28 bg-gray-100 rounded"></small>
                  </div>
                </TableCell>
              );
            }
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={secondaryActivityCategory?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{secondaryActivityCategory?.code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-36">
                    {secondaryActivityCategory?.name}
                  </small>
                </div>
              </TableCell>
            );

          case "top_region":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-6 bg-gray-200 rounded"></span>
                    <small className="h-3 w-16 bg-gray-100 rounded"></small>
                  </div>
                </TableCell>
              );
            }
            const topRegion = unit.physical_region_path
              ? allRegions.find(
                  ({ path }: Tables<'region_used'>) =>
                    path ===
                    (unit.physical_region_path as string | null)?.split(".")[0]
                )
              : undefined;
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={topRegion?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{topRegion?.code}</span>
                  <small className="text-gray-700 max-w-20 overflow-hidden text-ellipsis whitespace-nowrap">
                    {topRegion?.name}
                  </small>
                </div>
              </TableCell>
            );

          case "region":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-10 bg-gray-200 rounded"></span>
                    <small className="h-3 w-16 bg-gray-100 rounded"></small>
                  </div>
                </TableCell>
              );
            }
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={region?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{region?.code}</span>
                  <small className="text-gray-700 max-w-20 overflow-hidden text-ellipsis whitespace-nowrap">
                    {region?.name}
                  </small>
                </div>
              </TableCell>
            );

          case "statistic":
            if (column.type === "Adaptable" && column.stat_code) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  {(() => {
                    const metric = unit.stats_summary[column.stat_code];
                    let valueToDisplay: number | string | null = null;

                    if (metric && ("sum" in metric)) {
                      valueToDisplay = metric.sum !== undefined ? metric.sum : null;
                    } else {
                      valueToDisplay = "-";
                    }
                    return thousandSeparator(valueToDisplay);
                  })()}
                </TableCell>
              );
            }
            return null;

          case "unit_counts":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex flex-col space-y-0.5 leading-tight whitespace-nowrap">
                  {unit.included_enterprise_count != null &&
                    unit.included_enterprise_count > 0 && (
                      <small className="text-gray-700">
                        Enterprises: {unit.included_enterprise_count}
                      </small>
                    )}
                  {unit.included_legal_unit_count != null &&
                    unit.included_legal_unit_count > 0 && (
                      <small className="text-gray-700">
                        Legal Units: {unit.included_legal_unit_count}
                      </small>
                    )}
                  {unit.included_establishment_count != null &&
                    unit.included_establishment_count > 0 && (
                      <small className="text-gray-700">
                        Establishments: {unit.included_establishment_count}
                      </small>
                    )}
                </div>
              </TableCell>
            );

          case "sector":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={unit.sector_name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{unit.sector_code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-32">
                    {unit.sector_name}
                  </small>
                </div>
              </TableCell>
            );
          case "legal_form":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={unit.legal_form_name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span>{unit.legal_form_code}</span>
                  <small className="text-gray-700 max-w-32 overflow-hidden text-ellipsis whitespace-nowrap lg:max-w-32">
                    {unit.legal_form_name}
                  </small>
                </div>
              </TableCell>
            );
          case "physical_address":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={physical_address}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <small className="text-gray-700 min-w-40 line-clamp-3 lg:max-w-48">
                    {physical_address}
                  </small>
                </div>
              </TableCell>
            );

          case "physical_country_iso_2":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span className="whitespace-nowrap">
                    {unit.physical_country_iso_2}
                  </span>
                </div>
              </TableCell>
            );
          case "domestic":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex flex-col space-y-0.5 leading-tight">
                  <span className="text-gray-700 whitespace-nowrap">
                    {unit.domestic ? (
                      <SquareCheckBig size={16} />
                    ) : (
                      <Square size={16} />
                    )}
                  </span>
                </div>
              </TableCell>
            );
          case "birth_date":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={unit.birth_date ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span className="whitespace-nowrap">{unit.birth_date}</span>
                </div>
              </TableCell>
            );
          case "death_date":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={unit.death_date ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span className="whitespace-nowrap">{unit.death_date}</span>
                </div>
              </TableCell>
            );
          case "status":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-16 bg-gray-200 rounded"></span>
                  </div>
                </TableCell>
              );
            }
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={status?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span className="whitespace-nowrap">{status?.name}</span>
                </div>
              </TableCell>
            );
          case "unit_size":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-20 bg-gray-200 rounded"></span>
                  </div>
                </TableCell>
              );
            }
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div
                  title={unitSize?.name ?? ""}
                  className="flex flex-col space-y-0.5 leading-tight"
                >
                  <span className="whitespace-nowrap">{unitSize?.name}</span>
                </div>
              </TableCell>
            );
          case "data_sources":
            // Show loading placeholder while lookup data is being fetched
            if (!searchPageDataReady) {
              return (
                <TableCell
                  key={`cell-${bodyCellSuffix(unit, column)}`}
                  className={getCellClassName(column)}
                >
                  <div className="flex flex-col space-y-0.5 leading-tight animate-pulse">
                    <span className="h-4 w-12 bg-gray-200 rounded"></span>
                  </div>
                </TableCell>
              );
            }
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex flex-col space-y-0.5 leading-tight">
                  {dataSources.map((ds) => (
                    <Popover key={`dataSource-${ds?.id}`}>
                      <PopoverTrigger asChild>
                        <span className="cursor-pointer" title={ds?.name ?? ''}>
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
          case "last_edit":
            return (
              <TableCell
                key={`cell-${bodyCellSuffix(unit, column)}`}
                className={getCellClassName(column)}
              >
                <div className="flex flex-col space-y-0.5 leading-tight whitespace-nowrap">
                  <small className="text-gray-700">{formattedLastEditAt}</small>
                  <small className="text-gray-700">By {lastEditBy}</small>
                </div>
              </TableCell>
            );
        }
      })}
      <TableCell key="column-action" className="py-2 p-1 text-right sticky right-0 bg-white">
        <SearchResultTableRowDropdownMenu unit={unit} />
      </TableCell>
    </TableRow>
  );
};
