import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {useSearchContext} from "../search-provider";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import {SearchResultTableRow} from "@/app/search/components/search-result-table-row";

export default function SearchResultTable() {
    const {searchResult} = useSearchContext();

    return (
        <Table>
            <TableHeader className="bg-gray-100">
                <TableRow>
                    <SortableTableHead name="name">Name</SortableTableHead>
                    <SortableTableHead className="text-left" name="physical_region_path">Region</SortableTableHead>
                    <SortableTableHead className="text-right" name="employees">Employees</SortableTableHead>
                    <SortableTableHead className="text-left" name="primary_activity_category_path">Activity Category</SortableTableHead>
                    <TableHead />
                </TableRow>
            </TableHeader>
            <TableBody>
                {
                    !searchResult?.statisticalUnits.length && (
                        <TableRow>
                            <TableCell colSpan={5} className="text-center py-8">No results found</TableCell>
                        </TableRow>
                    )
                }
                {
                    searchResult?.statisticalUnits.map((unit) => {
                            return (
                                <SearchResultTableRow key={`${unit.unit_id}-${unit.unit_type}`} unit={unit}/>
                            )
                        }
                    )
                }
            </TableBody>
        </Table>
    )
}

