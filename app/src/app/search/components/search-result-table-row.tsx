import {Tables} from "@/lib/database.types";
import {useSearchContext} from "@/app/search/search-provider";
import {TableCell, TableRow} from "@/components/ui/table";
import {cn} from "@/lib/utils";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {StatisticalUnitDetailsLink} from "@/components/statistical-unit-details-link";
import SearchResultTableRowDropdownMenu from "@/app/search/components/search-result-table-row-dropdown-menu";

interface SearchResultTableRowProps {
  unit: Tables<"statistical_unit">;
  className?: string;
}

export const SearchResultTableRow = ({unit, className}: SearchResultTableRowProps) => {
  const {regions, activityCategories} = useSearchContext();
  const {
    unit_type: type,
    unit_id: id,
    name,
    primary_activity_category_path,
    physical_region_path,
    tax_reg_ident,
    employees
  } = unit;

  const getRegionByPath = (physical_region_path: unknown) =>
    regions.find(({path}) => path === physical_region_path);

  const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
    activityCategories.find(({path}) => path === primary_activity_category_path);

  const activityCategory = getActivityCategoryByPath(primary_activity_category_path);
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
  }

  return (
    <TableRow key={`${type}_${id}`} className={cn('', className)}>
      <TableCell className="py-2">
        <div className="flex items-center space-x-3 leading-none">
          <StatisticalUnitIcon type={type} className="w-5"/>
          <div className="flex flex-col space-y-1.5 flex-1">
            {
              type && id && name ? (
                <StatisticalUnitDetailsLink id={id} type={type}>{name}</StatisticalUnitDetailsLink>
              ) : (
                <span className="font-medium">{name}</span>
              )
            }
            <small className="text-gray-700">{tax_reg_ident} | {prettifyUnitType(type)}</small>
          </div>
        </div>
      </TableCell>
      <TableCell className="text-left py-2">
        {region?.name}
      </TableCell>
      <TableCell className="text-right py-2">
        {employees ?? '-'}
      </TableCell>
      <TableCell
        title={activityCategory?.name ?? ''}
        className="text-left py-2 pl-4 pr-2 max-w-36 lg:max-w-72 overflow-hidden overflow-ellipsis whitespace-nowrap"
      >
        {activityCategory?.name ?? '-'}
      </TableCell>
      <TableCell className="p-1 text-right">
        <SearchResultTableRowDropdownMenu unit={unit}/>
      </TableCell>
    </TableRow>
  )
}
