"use client";
import { Table, TableBody } from "@/components/ui/table";
import { StatisticalUnitTableRow } from "@/app/search/components/statistical-unit-table-row";
import SearchBulkActionButton from "@/app/search/components/search-bulk-action-button";
import { useSelectionContext } from "@/app/search/use-selection-context";
import { useRegionLevel } from "@/app/search/hooks/useRegionLevel";

export const Selection = () => {
  const { selected } = useSelectionContext();
  const { regionLevel } = useRegionLevel();

  if (selected.length === 0) return null;

  return (
    <div className="space-y-3">
      <div className="rounded-md border">
        <Table>
          <TableBody>
            {selected.map((unit) => {
              return (
                <StatisticalUnitTableRow
                  key={`selection_${unit.unit_type}_${unit.unit_id}`}
                  unit={unit}
                  regionLevel={regionLevel}
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
