"use client";
import { Tables } from "@/lib/database.types";
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

interface SearchResultTableRowProps {
  unit: Tables<"statistical_unit">;
  className?: string;
  regionLevel: number;
}

export const StatisticalUnitTableRow = ({
  unit,
  className,
  regionLevel,
}: SearchResultTableRowProps) => {
  const { allRegions, allActivityCategories, allDataSources } = useSearchContext();
  const { statDefinitions, externalIdentTypes } = useBaseData();
  const { selected } = useSelectionContext();

  const isInBasket = selected.some(
    (s) => s.unit_id === unit.unit_id && s.unit_type === unit.unit_type
  );

  const {
    unit_type: type,
    unit_id: id,
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

  return (
    <TableRow className={cn("", className, isInBasket ? "bg-gray-100" : "")}>
      <TableCell className="py-2">
        <div
          className="flex items-center space-x-3 leading-tight"
          title={name ?? ""}
        >
          <StatisticalUnitIcon type={type} className="w-5" />
          <div className="flex flex-1 flex-col space-y-0.5 max-w-56">
            {type && id && name ? (
              <StatisticalUnitDetailsLink
                className="overflow-hidden overflow-ellipsis whitespace-nowrap"
                id={id}
                type={type}
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
      <TableCell
        title={region?.name ?? ""}
        className="py-2 text-left hidden lg:table-cell"
      >
        <div className="flex flex-col space-y-0.5 leading-tight">
          <span>{region?.code}</span>
          <small className="text-gray-700 max-w-20 overflow-hidden overflow-ellipsis whitespace-nowrap">
            {region?.name}
          </small>
        </div>
      </TableCell>
      {statDefinitions.map(({ code }) => (
        <TableCell key={code} className="py-2 text-right hidden lg:table-cell">
          {thousandSeparator(stats_summary[code!]?.sum)}
        </TableCell>
      ))}
      <TableCell
        className="py-2 text-left hidden lg:table-cell"
        title={sector_name ?? ""}
      >
        <div className="flex flex-col space-y-0.5 leading-tight">
          <span>{sector_code}</span>
          <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-32">
            {sector_name}
          </small>
        </div>
      </TableCell>
      <TableCell
        title={activityCategory?.name ?? ""}
        className="py-2 pl-4 pr-2 text-left hidden lg:table-cell "
      >
        <div className="flex flex-col space-y-0.5 leading-tight">
          <span>{activityCategory?.code}</span>
          <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-36">
            {activityCategory?.name}
          </small>
        </div>
      </TableCell>
      <TableCell className="py-2 text-left hidden lg:table-cell">
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
      <TableCell className="p-1 text-right">
        <SearchResultTableRowDropdownMenu unit={unit} />
      </TableCell>
    </TableRow>
  );
};
