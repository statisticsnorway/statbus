import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {StatisticalUnitDetailsLink} from "@/components/statistical-unit-details-link";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {useSearchContext} from "../search-provider";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import {Checkbox} from "@/components/ui/checkbox";

export default function SearchResultTable() {
  const {
    toggle,
    selected,
    searchResult,
    regions,
    activityCategories
  } = useSearchContext();

  const getRegionByPath = (physical_region_path: unknown) =>
    regions.find(({path}) => path === physical_region_path);

  const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
    activityCategories.find(({path}) => path === primary_activity_category_path);

  const prettifyUnitType = (type: UnitType): string => {
    switch (type) {
      case "enterprise":
        return "Enterprise";
      case "enterprise_group":
        return "Enterprise Group";
      case "legal_unit":
        return "Legal Unit";
      case "establishment":
        return "Establishment";
    }
  }

  return (
    <Table>
      <TableHeader className="bg-gray-100">
        <TableRow>
          <TableHead className="flex items-center"><Checkbox/></TableHead>
          <SortableTableHead name="name">Name</SortableTableHead>
          <SortableTableHead className="text-left" name="physical_region_path">Region</SortableTableHead>
          <SortableTableHead className="text-right" name="employees">Employees</SortableTableHead>
          <SortableTableHead className="text-left" name="primary_activity_category_path">Activity
            Category</SortableTableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {
          searchResult?.statisticalUnits?.map((unit) => {
              const {
                unit_type,
                unit_id,
                tax_reg_ident,
                name,
                physical_region_path,
                primary_activity_category_path,
                employees
              } = unit;

              const activityCategory = getActivityCategoryByPath(primary_activity_category_path);
              const region = getRegionByPath(physical_region_path);
              const isSelected = selected.find(s => s.id === unit_id && s.type === unit_type);

              return (
                <TableRow key={`${unit_type}_${unit_id}`}>
                  <TableCell className="py-2">
                    <div className="flex items-center">
                      <Checkbox checked={!!isSelected} onCheckedChange={() => toggle(unit_id, unit_type)}/>
                    </div>
                  </TableCell>
                  <TableCell className="py-2">
                    <div className="flex items-center space-x-3 leading-none">
                      <StatisticalUnitIcon type={unit_type} className="w-5"/>
                      <div className="flex flex-col space-y-1.5 flex-1">
                        {
                          unit_type && unit_id && name ? (
                            <StatisticalUnitDetailsLink id={unit_id} type={unit_type}>{name}</StatisticalUnitDetailsLink>
                          ) : (
                            <span className="font-medium">{name}</span>
                          )
                        }
                        <small className="text-gray-700">{tax_reg_ident} | {prettifyUnitType(unit_type)}</small>
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
                </TableRow>
              )
            }
          )
        }
      </TableBody>
    </Table>
  )
}
