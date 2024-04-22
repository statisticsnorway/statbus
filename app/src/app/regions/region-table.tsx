"use client";
import { Table, TableBody, TableHeader, TableRow } from "@/components/ui/table";
import RegionTableRow from "./region-table-row";
import { useRegionContext } from "./use-region-context";
import { Loader } from "lucide-react";
import { cn } from "@/lib/utils";
import RegionSortableTableHead from "./region-sortable-table-head";

export default function RegionTable() {
  const { regionsResult, isLoading } = useRegionContext();

  return (
    <div className="relative">
      <Table className={cn("bg-white", isLoading && "blur-md")}>
        <TableHeader className="bg-gray-50">
          <TableRow>
            <RegionSortableTableHead name="code">Code</RegionSortableTableHead>
            <RegionSortableTableHead name="name">Name</RegionSortableTableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {regionsResult?.regions?.map((region) => {
            return <RegionTableRow key={region.id} region={region} />;
          })}
        </TableBody>
      </Table>
      {isLoading && (
        <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
          <Loader className="animate-spin duration-1000 h-8 w-8 stroke-ssb-dark" />
        </div>
      )}
    </div>
  );
}
