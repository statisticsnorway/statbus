import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {useSearchContext} from "../search-provider";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import {Checkbox} from "@/components/ui/checkbox";
import {Tables} from "@/lib/database.types";
import {SearchResultTableRow} from "@/app/search/components/search-result-table-row";
import {useCartContext} from "@/app/search/cart-provider";

export default function SearchResultTable() {
    const {searchResult} = useSearchContext();
    const {selected} = useCartContext();

    const selectedInPreviousSearch: Tables<"statistical_unit">[] = selected
        .filter(s => !searchResult?.statisticalUnits?.find(u => u.unit_id === s.unit_id && u.unit_type === s.unit_type));

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
                {
                    selectedInPreviousSearch.length > 0 && (
                        <TableRow>
                            <TableCell colSpan={5} className="text-center font-medium text-zinc-500 py-4 bg-gray-100">
                                Selected units from previous search
                            </TableCell>
                        </TableRow>
                    )
                }
                {
                    selectedInPreviousSearch.map((unit) => {
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

