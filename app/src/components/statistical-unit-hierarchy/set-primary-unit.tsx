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
import { useTimeFrame } from "@/atoms/app-derived";
import { useDetailsPageData } from "@/atoms/edits";
import { TimeFramePanel, dateOutsideBounds, framePeriod, type ValidityChoice } from "@/components/time-frame-panel";
import { useFixedFrameConfirmation } from "@/components/fixed-frame-confirmation";
import { useUnitExistence } from "@/components/form/timeline-skeleton-view";
import { setPrimaryEstablishment } from "@/app/establishments/[id]/update-establishment-server-actions";
import { setPrimaryLegalUnit } from "@/app/legal-units/[id]/update-legal-unit-server-actions";
import { liveFrame, primaryChangePeriod } from "./primary-change-period";
import { primaryTimeline, type PrimaryRow } from "./primary-timeline";
import useSWR from "swr";
import { useAtomValue } from "jotai";
import { restClientAtom } from "@/atoms/rest-client";
import { FieldTimeline } from "@/components/form/field-timeline-view";
import { editPeriods, selectionRange, toggleSelection } from "@/components/form/field-timeline";
import type { TimeFramePanelMode } from "@/components/time-frame-panel";

const PRIMARY_CHANGE_BY_TYPE = {
  establishment: {
    label: "establishment",
    action: setPrimaryEstablishment,
    table: "establishment",
    parentColumn: "legal_unit_id",
    flag: "primary_for_legal_unit",
  },
  legal_unit: {
    label: "legal unit",
    action: setPrimaryLegalUnit,
    table: "legal_unit",
    parentColumn: "enterprise_id",
    flag: "primary_for_enterprise",
  },
} as const;

/**
 * Who is primary when among the parent's units (primaryTimeline), read when the dialog opens: the
 * rows of every unit under the same parent with their primary flag.
 */
function usePrimaryTimeline(type: keyof typeof PRIMARY_CHANGE_BY_TYPE, id: number, open: boolean) {
  const client = useAtomValue(restClientAtom);
  const { table, parentColumn, flag } = PRIMARY_CHANGE_BY_TYPE[type];
  const { data } = useSWR(open && client ? ["primary-timeline", table, id] : null, async () => {
    // The table is chosen by the unit type (PRIMARY_CHANGE_BY_TYPE), as in useUnitExistence.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = client as any;
    const { data: own, error: ownError } = await db.from(table).select(parentColumn).eq("id", id).limit(1);
    if (ownError) throw ownError;
    const parent = own?.[0]?.[parentColumn];
    if (parent == null) return [] as PrimaryRow[];
    const { data: rows, error } = await db
      .from(table)
      .select(`id,name,valid_from,valid_to,${flag}`)
      .eq(parentColumn, parent)
      .order("valid_from");
    if (error) throw error;
    return (rows as Record<string, unknown>[]).map(
      (r): PrimaryRow => ({
        id: r.id as number,
        name: r.name as string | null,
        valid_from: r.valid_from as string,
        valid_to: r.valid_to as string,
        primary: r[flag] as boolean | null,
      })
    );
  });
  return data;
}

/**
 * Makes a unit its parent's primary over a stretch of time (2f4c0z), like any other edit: the Time
 * frame panel starts on the live frame and also offers the other frames and Specific dates. Before
 * and after the chosen period the primary stays as it was; a change reaching a past frame asks
 * first (Change a past frame?).
 */
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
  const { timeFrames } = useTimeFrame();
  const { dataSources } = useDetailsPageData();
  const [open, setOpen] = useState(false);
  const [choice, setChoice] = useState<ValidityChoice>("frame");
  const [frameIdent, setFrameIdent] = useState<string | null>(null);
  const [validFrom, setValidFrom] = useState<string | null>(null);
  const [validTo, setValidTo] = useState<string | null>(null);
  const [mode, setMode] = useState<TimeFramePanelMode>("frame");
  const [ticked, setTicked] = useState<number[]>([]);
  const [isPending, startTransition] = useTransition();
  const { mutate } = useSWRConfig();
  const { toast } = useToast();
  const { ask, dialog } = useFixedFrameConfirmation();

  const live = liveFrame(timeFrames);
  const frame = timeFrames.find((tf) => tf.ident === (frameIdent ?? live?.ident)) ?? null;
  // Timeline: who is primary when, cut at frame edges like an edit's field timeline; the ticked
  // stretch is the period (selectionRange).
  const primaryRows = usePrimaryTimeline(type, id, open);
  const timelinePeriods = primaryRows ? editPeriods(primaryTimeline(primaryRows), timeFrames) : [];
  const tickedRange = mode === "timeline" ? selectionRange(timelinePeriods, ticked) : null;
  const period =
    mode === "timeline"
      ? tickedRange
      : primaryChangePeriod(choice, frame, validFrom, validTo);
  // Where the unit exists, the same bound as an edit's Specific dates (edit-metadata-controls): a date
  // outside it is refused at the date field, before anything is sent.
  const existence = useUnitExistence(
    open ? { table: type, match: { [`${type}_id`]: id }, column: `primary_for_${type === "establishment" ? "legal_unit" : "enterprise"}` } : undefined
  );
  const dateBounds = existence?.length
    ? { from: existence[0].validFrom, to: existence[existence.length - 1].validTo }
    : undefined;
  const outside =
    mode === "frame" && choice === "dates"
      ? dateOutsideBounds(validFrom, dateBounds) ?? dateOutsideBounds(validTo, dateBounds)
      : null;
  const periodText = period
    ? framePeriod({ valid_from: period.validFrom, valid_to: period.validTo })
    : null;

  const openChange = (next: boolean) => {
    if (next) {
      setChoice("frame");
      setFrameIdent(live?.ident ?? null);
      setValidFrom(null);
      setValidTo(null);
      setMode("frame");
      setTicked([]);
    }
    setOpen(next);
  };

  const save = () =>
    startTransition(async () => {
      if (!period) return;
      const result = await action(id, period.validFrom, period.validTo);
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
        description: `${name} is the primary ${label} of ${parentName} in ${periodText}.`,
        className: "border-green-700 bg-green-100 text-green-700",
      });
    });

  const confirm = () => {
    if (!period) return;
    if (!ask(period.validFrom, period.validTo, save)) save();
  };

  return (
    <>
      <Popover open={open} onOpenChange={openChange}>
        <PopoverTrigger asChild>
          <Button
            variant="outline"
            size="sm"
            className="h-6 px-2.5 text-xs"
          >
            Set as primary
          </Button>
        </PopoverTrigger>
        <PopoverContent align="end" className="w-[28rem] space-y-3" data-set-primary-dialog>
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
          <TimeFramePanel
            idPrefix={`set-primary-${type}-${id}`}
            timeFrames={timeFrames}
            mode={mode}
            onModeChange={setMode}
            timeline={
              <FieldTimeline
                periods={timelinePeriods}
                selected={ticked}
                onToggle={(i) => setTicked((s) => toggleSelection(s, i))}
              />
            }
            choice={choice}
            onChoiceChange={setChoice}
            frameIdent={frame?.ident ?? null}
            onFrameChange={setFrameIdent}
            validFrom={validFrom}
            validTo={validTo}
            onValidFromChange={setValidFrom}
            onValidToChange={setValidTo}
            dataSources={dataSources}
            dataSourceCode={null}
            onDataSourceChange={() => {}}
            comment={null}
            onCommentChange={() => {}}
            hideMetadata
            dateBounds={dateBounds}
          />
          <p className="text-xs text-zinc-500">
            {periodText
              ? currentPrimaryName
                ? `In ${periodText}, ${currentPrimaryName} will no longer be primary. Before and after, the primary stays as it is.`
                : `${name} becomes primary in ${periodText}.`
              : mode === "timeline"
                ? "Tick the stretch where it becomes primary."
                : "Choose a time frame or a From date."}
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
            <Button size="sm" onClick={confirm} disabled={isPending || !period || outside !== null}>
              {isPending ? "Saving…" : "Set as primary"}
            </Button>
          </div>
        </PopoverContent>
      </Popover>
      {dialog}
    </>
  );
}
