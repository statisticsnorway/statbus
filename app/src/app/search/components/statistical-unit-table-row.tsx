"use client";
import { Tables } from "@/lib/database.types";
import { TableCell, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { StatisticalUnitDetailsLink } from "@/components/statistical-unit-details-link";
import SearchResultTableRowDropdownMenu from "@/app/search/components/search-result-table-row-dropdown-menu";
import { Bug } from "lucide-react";
import { useCartContext } from "@/app/search/use-cart-context";
import { useSearchContext } from "@/app/search/use-search-context";
import { thousandSeparator } from "@/lib/number-utils";
import { StatisticalUnit } from "@/app/types";
import { useCustomConfigContext } from "@/app/use-custom-config-context";

interface SearchResultTableRowProps {
  unit: Tables<"statistical_unit">;
  className?: string;
}

export const StatisticalUnitTableRow = ({
  unit,
  className,
}: SearchResultTableRowProps) => {
  const { regions, activityCategories } = useSearchContext();
  const { selected } = useCartContext();
  const { statDefinitions, externalIdentTypes } = useCustomConfigContext();

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
  } = unit as StatisticalUnit;

  const external_ident = external_idents[externalIdentTypes?.[0]?.code];

  const getRegionByPath = (physical_region_path: unknown) =>
    regions.find(({ path }) => path === physical_region_path);

  const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
    activityCategories.find(
      ({ path }) => path === primary_activity_category_path
    );

  /* TODO - Remove this once the search results include the activity category and region names
   * Until activity category and region names are included in the search results,
   * we need to provide activity categories and regions via the search provider
   * so that the names can be displayed in the search results.
   *
   * A better solution would be to include the names in the search results
   * so that we do not need any blocking calls to supabase here.
   */

  const activityCategory = getActivityCategoryByPath(
    primary_activity_category_path
  );

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
              <span>{external_ident}</span>
              <span>|</span>
              <span>{prettifyUnitType(type)}</span>
              {invalid_codes && (
                <>
                  <span>|</span>
                  <div title={JSON.stringify(invalid_codes)}>
                    <Bug className="h-3 w-3 stroke-gray-600" />
                  </div>
                </>
              )}
            </small>
          </div>
        </div>
      </TableCell>
      <TableCell className="py-2 text-left hidden lg:table-cell">
        <div className="flex flex-col space-y-0.5 leading-tight">
          <span>{region?.code}</span>
          <small className="text-gray-700 max-w-24 overflow-hidden overflow-ellipsis whitespace-nowrap">
            {region?.name}
          </small>
        </div>
      </TableCell>
      <TableCell className="py-2 text-right hidden lg:table-cell">
        {thousandSeparator(stats_summary[statDefinitions?.[0]?.code]?.sum)}
      </TableCell>
      <TableCell className="py-2 text-right hidden lg:table-cell">
        {thousandSeparator(stats_summary[statDefinitions?.[1]?.code]?.sum)}
      </TableCell>
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
          <small className="text-gray-700 max-w-32 overflow-hidden overflow-ellipsis whitespace-nowrap lg:max-w-40">
            {activityCategory?.name}
          </small>
        </div>
      </TableCell>
      <TableCell className="p-1 text-right">
        <SearchResultTableRowDropdownMenu unit={unit} />
      </TableCell>
    </TableRow>
  );
};
