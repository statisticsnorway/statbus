import {Table, TableBody, TableCell, TableHeader, TableRow} from "@/components/ui/table";
import {StatisticalUnitDetailsLink} from "@/components/statistical-unit-details-link";
import {StatisticalUnitIcon} from "@/components/statistical-unit-icon";
import {useSearchContext} from "../search-provider";
import SortableTableHead from "@/app/search/components/sortable-table-head";

export default function SearchResultTable() {
  const {searchResult, regions, activityCategories} = useSearchContext();

  const getRegionByPath = (physical_region_path: unknown) =>
    regions.find(({path}) => path === physical_region_path);

  const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
    activityCategories.find(({path}) => path === primary_activity_category_path);

  return (
    <Table>
      <TableHeader className="bg-gray-100">
        <TableRow>
          <SortableTableHead name="name">Name</SortableTableHead>
          <SortableTableHead className="text-left" name="physical_region_path">Region</SortableTableHead>
          <SortableTableHead className="text-right" name="employees">Employees</SortableTableHead>
          <SortableTableHead className="text-right" name="primary_activity_category_path">Activity Category</SortableTableHead>
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
              return (
                <TableRow key={`${unit_type}_${unit_id}`}>
                  <TableCell className="px-3 py-2 flex items-center space-x-3 leading-none">
                    <StatisticalUnitIcon type={unit_type} size={20}/>
                    <div className="flex flex-col space-y-1.5 flex-1">
                      {
                        unit_type && unit_id && name ? (
                          <StatisticalUnitDetailsLink id={unit_id} type={unit_type} name={name}/>
                        ) : (
                          <span className="font-medium">{name}</span>
                        )
                      }
                      <small className="text-gray-700">{tax_reg_ident}</small>
                    </div>
                  </TableCell>
                  <TableCell className="text-left py-1">
                    {getRegionByPath(physical_region_path)?.name}
                  </TableCell>
                  <TableCell className="text-right py-1">
                    {employees ?? '-'}
                  </TableCell>
                  <TableCell className="text-right py-1 px-4">
                    {getActivityCategoryByPath(primary_activity_category_path)?.code}
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
