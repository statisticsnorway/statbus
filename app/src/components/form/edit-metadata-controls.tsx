"use client";

import { useDetailsPageData, useEditManager } from "@/atoms/edits";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { format } from "date-fns";
import { CalendarIcon } from "lucide-react";

interface EditMetadataControlsProps {
  fieldId: string;
}

export function EditMetadataControls({ fieldId }: EditMetadataControlsProps) {
  const { dataSources } = useDetailsPageData();
  const {
    currentEdit,
    setEditDataSourceId,
    setEditComment,
    setEditValidFrom,
    setEditValidTo,
  } = useEditManager();

  return (
    <>
      <input
        type="hidden"
        name="valid_from"
        value={currentEdit.validFrom ?? ""}
      />
      <input
        type="hidden"
        name="valid_until"
        value={currentEdit.validTo ?? ""}
      />
      <Separator className="mt-1" />
      <div className="grid grid-cols-3 gap-4">
        <div>
          <Label
            htmlFor={`${fieldId}-datasource`}
            className="text-xs uppercase text-gray-600"
          >
            Data Source
          </Label>
          <Select
            name="data_source_id"
            value={currentEdit.dataSourceId ?? ""}
            onValueChange={setEditDataSourceId}
          >
            <SelectTrigger
              id={`${fieldId}-datasource`}
              className={"w-full border-zinc-300 bg-white"}
            >
              <SelectValue placeholder="Select data source" />
            </SelectTrigger>
            <SelectContent>
              {dataSources.map((option) => (
                <SelectItem key={option.id} value={option.id?.toString() ?? ""}>
                  {option.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div>
          <Label
            htmlFor={`${fieldId}-validfrom`}
            className="text-xs uppercase text-gray-600"
          >
            Valid From
          </Label>
          <div className="relative">
            <Input
              id={`${fieldId}-validfrom`}
              type="text"
              placeholder="yyyy-mm-dd"
              value={currentEdit.validFrom ?? ""}
              onChange={(e) => setEditValidFrom(e.target.value)}
              className="bg-white border-zinc-300"
            />
            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant={"ghost"}
                  className="absolute right-0 top-0 h-full rounded-l-none px-3"
                >
                  <CalendarIcon className="h-4 w-4" />
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0">
                <Calendar
                  mode="single"
                  selected={
                    currentEdit.validFrom &&
                    !isNaN(new Date(currentEdit.validFrom).getTime())
                      ? new Date(currentEdit.validFrom)
                      : undefined
                  }
                  onSelect={(date) =>
                    setEditValidFrom(date ? format(date, "yyyy-MM-dd") : "")
                  }
                />
              </PopoverContent>
            </Popover>
          </div>
        </div>
        <div>
          <Label
            htmlFor={`${fieldId}-validto`}
            className="text-xs uppercase text-gray-600"
          >
            Valid To
          </Label>
          <div className="relative">
            <Input
              id={`${fieldId}-validto`}
              type="text"
              placeholder="yyyy-mm-dd"
              value={currentEdit.validTo ?? ""}
              onChange={(e) => setEditValidTo(e.target.value)}
              className="bg-white border-zinc-300"
            />
            <Popover>
              <PopoverTrigger asChild>
                <Button
                  variant={"ghost"}
                  className="absolute right-0 top-0 h-full rounded-l-none px-3"
                >
                  <CalendarIcon className="h-4 w-4" />
                </Button>
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0">
                <div className="p-2">
                  <Button
                    variant="outline"
                    className="w-full"
                    onClick={() => setEditValidTo("infinity")}
                  >
                    Set to Infinity
                  </Button>
                </div>
                <Separator />
                <Calendar
                  mode="single"
                  selected={
                    currentEdit.validTo &&
                    !isNaN(new Date(currentEdit.validTo).getTime())
                      ? new Date(currentEdit.validTo)
                      : undefined
                  }
                  onSelect={(date) =>
                    setEditValidTo(date ? format(date, "yyyy-MM-dd") : "")
                  }
                />
              </PopoverContent>
            </Popover>
          </div>
        </div>
      </div>
      <div>
        <Label
          htmlFor={`${fieldId}-comment`}
          className="text-xs uppercase text-gray-600"
        >
          Edit Comment
        </Label>
        <Input
          id={`${fieldId}-comment`}
          name="edit_comment"
          type="text"
          className={`bg-white disabled:opacity-80 border-zinc-300`}
          value={currentEdit.editComment ?? ""}
          onChange={(e) => setEditComment(e.target.value)}
          placeholder="Optional comment"
        />
      </div>
    </>
  );
}
