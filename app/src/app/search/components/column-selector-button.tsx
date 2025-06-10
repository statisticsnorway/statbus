"use client";
import { Button } from "@/components/ui/button";
import { Settings2 } from "lucide-react";
import { useTableColumnsManager as useTableColumns } from '@/atoms/hooks';
import { ColumnSelector } from "./column-selector";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
export const ColumnSelectorButton = () => {
  const { columns, toggleColumn, profiles, setProfile } = useTableColumns();
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="secondary"
          className="hidden lg:flex items-center ml-auto space-x-2 h-9 p-2"
        >
          <Settings2 size={17} />
          <span>Column Settings</span>
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
