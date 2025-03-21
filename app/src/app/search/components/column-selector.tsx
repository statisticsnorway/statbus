import { Check } from "lucide-react";
import { ColumnProfile, TableColumn } from "../search.d";
import { isEqual } from "moderndash";
import {
  Command,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from "@/components/ui/command";
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
    <Command>
      <CommandInput placeholder="Columns" />
      <CommandList>
        <CommandGroup heading="Profiles">
          <CommandItem
            onSelect={() => setProfile("Brief")}
            value="Brief"
            className="space-x-2"
          >
            <Check
              size={14}
              className={
                profiles && isEqual(columns, profiles["Brief"])
                  ? "opacity-100"
                  : "opacity-0"
              }
            />
            <span>Brief</span>
          </CommandItem>
          <CommandItem
            onSelect={() => setProfile("Regular")}
            value="Regular"
            className="space-x-2"
          >
            <Check
              size={14}
              className={
                profiles && isEqual(columns, profiles["Regular"])
                  ? "opacity-100"
                  : "opacity-0"
              }
            />
            <span>Regular</span>
          </CommandItem>
          <CommandItem
            onSelect={() => setProfile("All")}
            value="All"
            className="space-x-2"
          >
            <Check
              size={14}
              className={
                profiles && isEqual(columns, profiles["All"])
                  ? "opacity-100"
                  : "opacity-0"
              }
            />
            <span>All</span>
          </CommandItem>
        </CommandGroup>
        <CommandSeparator />
        <CommandGroup heading="Toggle Columns">
          {columns.map((column) => (
            <CommandItem
              key={`column-selector-${column.code}${column.type === "Adaptable" ? "-" + column.stat_code : ""}`}
              value={column.label}
              onSelect={() => onToggleColumn(column)}
              disabled={column.type == "Always" ? true : false}
              className="space-x-2"
            >
              <Check
                size={14}
                className={
                  column.type === "Always" || column.visible
                    ? "opacity-100"
                    : "opacity-0"
                }
              />
              <span>{column.label}</span>
            </CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </Command>
  );
}
