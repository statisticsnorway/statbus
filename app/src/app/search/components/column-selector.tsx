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
import { TableColumn } from "../search.d";

interface ColumnSelectorProps {
  columns: TableColumn[];
  onToggleColumn: (column: TableColumn) => void;
  onReset: () => void;
  isDefaultState: boolean;
}

export function ColumnSelector({ columns, onToggleColumn, onReset, isDefaultState }: ColumnSelectorProps) {
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
            key={`column-selector-${column.code}${column.type === 'Adaptable' ? '-' + column.stat_code : ''}`}
            checked={column.type == 'Always' ? true : column.visible}
            onCheckedChange={() => onToggleColumn(column)}
            disabled={column.type == 'Always' ? true : false}
          >
            {column.label}
          </DropdownMenuCheckboxItem>
        ))}
        {!isDefaultState && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuCheckboxItem
              onCheckedChange={onReset}
              checked={false}
              className="text-red-600 hover:text-red-700"
            >
              Reset to Default
            </DropdownMenuCheckboxItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
