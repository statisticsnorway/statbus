"use client";

import { ChevronRight } from "lucide-react";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { Badge } from "@/components/ui/badge";
import { useBaseData } from "@/atoms/base-data";
import { useDetailsPageData } from "@/atoms/edits";

type Item = { code: string | null; name: string | null };
function Row({
  label,
  column,
  items,
}: {
  label: string;
  column?: string;
  items: Item[];
}) {
  if (!items.length) return null;
  return (
    <>
      <div className="pt-0.5 text-sm text-muted-foreground">
        {label}
        {column && <span className="ml-1 font-mono text-xs">({column})</span>}
      </div>
      <div className="flex flex-wrap gap-1.5">
        {items.map((item) => (
          <Badge
            key={item.code}
            variant="outline"
            title={item.name ?? undefined}
            className="font-mono font-normal"
          >
            {item.code}
          </Badge>
        ))}
      </div>
    </>
  );
}

export function AvailableColumns() {
  const { externalIdentTypes, statDefinitions } = useBaseData();
  const { unitSizes, status, dataSources } = useDetailsPageData();
  return (
    <Collapsible className="overflow-hidden rounded-md border text-left">
      <CollapsibleTrigger className="group flex w-full items-center gap-2 px-4 py-2.5 text-sm font-medium hover:underline">
        <ChevronRight className="h-4 w-4 transition-transform group-data-[state=open]:rotate-90 " />
        Available columns and values
      </CollapsibleTrigger>
      <CollapsibleContent className="border-t px-4 py-3">
        <div className="grid grid-cols-[auto_1fr] items-start gap-x-6 gap-y-2.5">
          <h3 className="col-span-2 text-sm font-medium">Columns</h3>
          <Row label="External identifiers" items={externalIdentTypes} />
          <Row label="Statistical variables" items={statDefinitions} />
          <h3 className="col-span-2 mt-3 text-sm font-medium">
            Allowed values
          </h3>
          <Row label="Unit size" column="unit_size_code" items={unitSizes} />
          <Row label="Status" column="status_code" items={status} />
          <Row
            label="Data source"
            column="data_source_code"
            items={dataSources}
          />
        </div>
      </CollapsibleContent>
    </Collapsible>
  );
}
