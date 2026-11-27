"use client";
import { Button } from "@/components/ui/button";
import { Settings2 } from "lucide-react";
import { useTableColumnsManager as useTableColumns } from "@/atoms/search";
import { ColumnSelector } from "./column-selector";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

/**
 * Column settings (owner 2026-11-27): an icon in the table's own header, in the cell above the
 * rows' "⋯" menus, beside what it changes. It belongs to the list's table, so the map view, which
 * has no table, has none.
 */
export const ColumnSelectorButton = () => {
  const { columns, toggleColumn, profiles, setProfile } = useTableColumns();
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          title="Column settings"
          aria-label="Column settings"
          data-column-settings=""
        >
          <Settings2 className="h-4 w-4" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-[300px] p-0">
        <ColumnSelector
          columns={columns}
          onToggleColumn={toggleColumn}
          profiles={profiles}
          setProfile={setProfile}
        />
      </PopoverContent>
    </Popover>
  );
};
