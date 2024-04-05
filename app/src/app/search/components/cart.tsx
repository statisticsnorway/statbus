"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import SearchBulkActionButton from "@/app/search/components/search-bulk-action-button";
import { useCartContext } from "@/app/search/use-cart-context";

export const Cart = () => {
  const { selected } = useCartContext();

  if (selected.length === 0) return null;

  return (
    <div className="space-y-3">
      <div className="rounded-md border">
        <Table>
          <TableBody>
            {selected.map((unit) => {
              return (
                <StatisticalUnitTableRow
                  key={`${unit.unit_id}-${unit.unit_type}`}
                  unit={unit}
                />
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex items-center justify-end">
        <SearchBulkActionButton />
      </div>
    </div>
  );
};
