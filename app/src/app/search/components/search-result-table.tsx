import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {SearchResult} from "@/app/search/search.types";
import {Tables} from "@/lib/database.types";
import {StatisticalUnitDetailsLink} from "@/components/statistical-unit-details-link";

interface TableProps {
    readonly searchResult: SearchResult
    readonly regions: Tables<'region_used'>[]
    readonly activityCategories: Tables<'activity_category_available'>[]
}

export default function SearchResultTable({searchResult: {statisticalUnits}, regions = [], activityCategories = []}: TableProps) {
    const getRegionByPath = (physical_region_path: unknown) =>
        regions.find(({path}) => path === physical_region_path);

    const getActivityCategoryByPath = (primary_activity_category_path: unknown) =>
        activityCategories.find(({path}) => path === primary_activity_category_path);

    return (
        <Table>
            <TableHeader className="bg-gray-100">
                <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead className="text-left">Type</TableHead>
                    <TableHead className="text-left">Region</TableHead>
                    <TableHead className="text-right">Activity Category Code</TableHead>
                </TableRow>
            </TableHeader>
            <TableBody>
                {
                    statisticalUnits?.map((unit) => {
                            const {unit_type, unit_id, tax_reg_ident, name, physical_region_path, primary_activity_category_path} = unit;
                            return (
                                <TableRow key={`${unit_type}_${unit_id}`}>
                                    <TableCell className="p-2 flex flex-col">
                                        {
                                            unit_type && unit_id && name ? (
                                                <StatisticalUnitDetailsLink id={unit_id} type={unit_type} name={name}/>
                                            ) : (
                                                <span className="font-medium">{name}</span>
                                            )
                                        }
                                        <small className="text-gray-700">{tax_reg_ident}</small>
                                    </TableCell>
                                    <TableCell className="text-left">{unit_type}</TableCell>
                                    <TableCell className="text-left">{getRegionByPath(physical_region_path)?.name}</TableCell>
                                    <TableCell className="text-right p-2 px-4">{getActivityCategoryByPath(primary_activity_category_path)?.code}</TableCell>
                                </TableRow>
                            )
                        }
                    )
                }
            </TableBody>
        </Table>
    )
}
