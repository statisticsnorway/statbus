"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import SearchBulkActionButton from "@/app/search/components/search-bulk-action-button";
import { useCartContext } from "@/app/search/use-cart-context";
import { useBaseData } from "@/app/BaseDataClient";

export const Cart = () => {
  const { selected } = useCartContext();
  const { statDefinitions, externalIdentTypes } = useBaseData();

  if (selected.length === 0) return null;

  return (
    <div className="space-y-3">
      <div className="rounded-md border">
        <Table>
          <TableBody>
            {selected.map((unit) => {
              return (
                <StatisticalUnitTableRow
                  key={`cart_${unit.unit_type}_${unit.unit_id}`}
                  unit={unit} />
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
