"use client";
import { useState, useTransition } from "react";
import { useSWRConfig } from "swr";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { useToast } from "@/hooks/use-toast";
import { setPrimaryEstablishment } from "@/app/establishments/[id]/update-establishment-server-actions";
import { setPrimaryLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";

const PRIMARY_CHANGE_BY_TYPE = {
  establishment: { label: "establishment", action: setPrimaryEstablishment },
  legal_unit: { label: "legal unit", action: setPrimaryLegalUnit },
} as const;

export function SetPrimaryUnit({
  type,
  id,
  name,
  parentName,
  currentPrimaryName,
}: {
  readonly type: keyof typeof PRIMARY_CHANGE_BY_TYPE;
  readonly id: number;
  readonly name: string;
  readonly parentName: string;
  readonly currentPrimaryName?: string | null;
}) {
  const { label, action } = PRIMARY_CHANGE_BY_TYPE[type];
  const [open, setOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const { mutate } = useSWRConfig();
  const { toast } = useToast();

  const confirm = () =>
    startTransition(async () => {
      const result = await action(id);
      if (result.status === "error") {
        toast({
          title: `Could not change primary ${label}`,
          description: result.message,
          className: "border-red-700 bg-red-100 text-red-700",
        });
        return;
      }
      await mutate(
        (key) => Array.isArray(key) && ["hierarchy", "details"].includes(key[0])
      );
      setOpen(false);
      toast({
        title: `Primary ${label} changed`,
        description: `${name} is now the primary ${label} of ${parentName}.`,
        className: "border-green-700 bg-green-100 text-green-700",
      });
    });

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          className="h-6 px-2.5 text-xs"
        >
          Set as primary
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-96 space-y-3">
        <p className="text-sm font-semibold leading-snug text-zinc-900">
          Make {name} the primary {label} of {parentName}?
        </p>
        {currentPrimaryName && (
          <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
            <dt className="text-zinc-500">Now</dt>
            <dd>{currentPrimaryName}</dd>
            <dt className="text-zinc-500">New</dt>
            <dd className="font-semibold">{name}</dd>
          </dl>
        )}
        <p className="text-xs text-zinc-500">
          {currentPrimaryName
            ? `${currentPrimaryName} will no longer be primary. You can change it back at any time.`
            : `There is no primary ${label} today.`}
        </p>
        <div className="flex justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setOpen(false)}
            disabled={isPending}
          >
            Cancel
          </Button>
          <Button size="sm" onClick={confirm} disabled={isPending}>
            {isPending ? "Saving…" : "Set as primary"}
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  );
}
