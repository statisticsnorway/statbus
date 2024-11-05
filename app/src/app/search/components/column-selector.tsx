import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuCheckboxItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Settings2 } from "lucide-react";
import { ColumnProfile, TableColumn } from "../search.d";
import { isEqual } from "moderndash";

interface ColumnSelectorProps {
  columns: TableColumn[];
  onToggleColumn: (column: TableColumn) => void;
  profiles: Record<ColumnProfile, TableColumn[]>;
  setProfile: (profile: ColumnProfile) => void;
}

export function ColumnSelector({
  columns,
  onToggleColumn,
  profiles,
  setProfile,
}: ColumnSelectorProps) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="sm">
          <Settings2 className="h-4 w-4" />
          <span className="sr-only">Column Settings</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-[200px]">
        <DropdownMenuLabel>Toggle Columns</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {columns.map((column) => (
          <DropdownMenuCheckboxItem
            key={`column-selector-${column.code}${column.type === "Adaptable" ? "-" + column.stat_code : ""}`}
            checked={column.type == "Always" ? true : column.visible}
            onCheckedChange={() => onToggleColumn(column)}
            disabled={column.type == "Always" ? true : false}
          >
            {column.label}
          </DropdownMenuCheckboxItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuLabel>Profiles</DropdownMenuLabel>
        <DropdownMenuCheckboxItem
          checked={profiles && isEqual(columns, profiles["Brief"])}
          onCheckedChange={() => setProfile("Brief")}
        >
          Brief
        </DropdownMenuCheckboxItem>
        <DropdownMenuCheckboxItem
          checked={profiles && isEqual(columns, profiles["Regular"])}
          onCheckedChange={() => setProfile("Regular")}
        >
          Regular
        </DropdownMenuCheckboxItem>
        <DropdownMenuCheckboxItem
          checked={profiles && isEqual(columns, profiles["Detailed"])}
          onCheckedChange={() => setProfile("Detailed")}
        >
          Detailed
        </DropdownMenuCheckboxItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
