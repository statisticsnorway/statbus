import { TableHead, TableHeader, TableRow } from "@/components/ui/table";
import SortableTableHead from "@/app/search/components/sortable-table-head";
import { useBaseData } from "@/app/BaseDataClient";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight } from "lucide-react";

export const StatisticalUnitTableHeader = ({
  regionLevel,
  setRegionLevel,
  maxRegionLevel,
}: {
  readonly regionLevel: number;
  readonly setRegionLevel: (level: number) => void;
  readonly maxRegionLevel: number;
}) => {
  const { statDefinitions, externalIdentTypes } = useBaseData();

  return (
    <TableHeader className="bg-gray-50">
      <TableRow>
        <SortableTableHead name="name" label="Name">
          <small className="flex">
            {externalIdentTypes.map(({ code }) => code).join(" | ")}
          </small>
        </SortableTableHead>

        <SortableTableHead
          className="text-left hidden lg:table-cell [&>*]:align-middle"
          name="physical_region_path"
          label="Region"
        >
          <small className="flex items-center whitespace-nowrap">
            <Button
              variant="ghost"
              disabled={regionLevel === 1}
              onClick={() => setRegionLevel(regionLevel - 1)}
              className="h-4 w-4"
              size="icon"
            >
              <ChevronLeft />
            </Button>
            <span title="Region level">Level {regionLevel}</span>
            <Button
              variant="ghost"
              disabled={regionLevel === maxRegionLevel}
              onClick={() => setRegionLevel(regionLevel + 1)}
              className="h-4 w-4"
              size="icon"
            >
              <ChevronRight />
            </Button>
          </small>
        </SortableTableHead>
        {statDefinitions.map(({ code }) => (
          <SortableTableHead
            key={code}
            className="text-right hidden lg:table-cell [&>*]:capitalize"
            name={code!}
            label={code!}
          />
        ))}
        <SortableTableHead
          className="text-left hidden lg:table-cell"
          name="sector_path"
          label="Sector"
        />
        <SortableTableHead
          className="text-left hidden lg:table-cell"
          name="primary_activity_category_path"
          label="Activity Category"
        />
        <TableHead />
      </TableRow>
    </TableHeader>
  );
};
