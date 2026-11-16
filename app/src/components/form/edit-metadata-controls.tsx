"use client";

import { useRef } from "react";
import { useAtom, useAtomValue, useSetAtom } from "jotai";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useFixedFrameConfirmation } from "@/components/fixed-frame-confirmation";
import {
  TimeFramePanel,
  dateOutsideBounds,
  type TimeFramePanelMode,
  type ValidityChoice,
} from "@/components/time-frame-panel";
import {
  editApprovedAtom,
  editChangesNeedingApprovalAtom,
  useDetailsPageData,
  useEditManager,
} from "@/atoms/edits";
import { useTimeFrame } from "@/atoms/app-derived";
import { Separator } from "@/components/ui/separator";
import { Checkbox } from "@/components/ui/checkbox";
import { useChangeEditFrame } from "./use-start-edit";
import { ChangedSource, FieldTimeline, PeriodChangeView, useFieldTimeline } from "./field-timeline-view";
import { opensInTimeline, periodOn, periodsInRange, selectionRange, toggleSelection } from "./field-timeline";
import { TimelineSkeleton, useUnitExistence } from "./timeline-skeleton-view";
import { skeletonPieces, skeletonSelectionRange } from "./timeline-skeleton";
import { capToExistence } from "./unit-existence";
import {
  FrameRemovalSummary,
  isRemovable,
  RemovalTimeline,
  TickAllPieces,
  useFrameRemovalPeriod,
  useRemovalPieces,
} from "./remove-record-button";
import { piecesInPeriod } from "./removal";
import { cn } from "@/lib/utils";
import { editChanges, needsApproval } from "./edit-changes";
import { useFormValues } from "./use-form-values";
import { useEditAnchor } from "./use-edit-anchor";

interface EditMetadataControlsProps {
  fieldId: string;
}

/**
 * Where an edit applies and where it comes from: the Time frame panel, the
 * same as on the import pages (components/time-frame-panel.tsx). The edit
 * opens on the frame the user is looking at and covers the shown value's
 * stretch in it (useStartEdit); the Frame menu also offers Specific dates.
 * Timeline shows the field's history and the edit applies to the ticked
 * stretch of it; Edit opens there when the shown value is not the field's
 * newest. Change | Remove (a record the unit has) works in both views. Data
 * source and Comment are stored with a change. With several periods ticked,
 * the timeline shows what the save changes in each (edit-changes), and a save
 * that changes a period other than the one the form shows waits for the
 * user's approval (SaveApproval). A save that reaches into a relative or fixed
 * frame asks first.
 */
export function EditMetadataControls({ fieldId }: EditMetadataControlsProps) {
  const { dataSources } = useDetailsPageData();
  const {
    currentEdit,
    setEditDataSourceId,
    setEditComment,
    setEditValidFrom,
    setEditValidTo,
    setEditRemoving,
    setEditView,
    setEditValidityChoice,
  } = useEditManager();
  const { timeFrames, selectedTimeFrame } = useTimeFrame();
  const changeEditFrame = useChangeEditFrame();
  // The view and the dating choice live with the edit (Remove follows them).
  const mode: TimeFramePanelMode = currentEdit.view ?? "frame";
  const choice: ValidityChoice = currentEdit.validityChoice ?? "frame";

  // The field's timeline, when the field names its rows. The edit's dates are
  // the ticked stretch; the ticks are read back from the dates, so the frame
  // and Advanced views and the Timeline view always agree.
  const { periods, loaded } = useFieldTimeline(currentEdit.source);
  const selected = periodsInRange(periods, currentEdit.validFrom, currentEdit.validTo);
  // What a save does to each ticked period (owner 2026-11-16): the form holds
  // the anchor's values (useEditAnchor), and a save writes them over every
  // ticked period; changes to periods other than the anchor wait for approval.
  const anchorRef = useRef<HTMLDivElement>(null);
  const columns = currentEdit.source
    ? [currentEdit.source.column].flat()
    : [];
  const formValues = useFormValues(anchorRef, columns);
  const { anchor, shown } = useEditAnchor(true, currentEdit.source);
  const changes = editChanges(periods, selected, formValues, currentEdit.dataSourceId);
  const changesKey = JSON.stringify([...changes.entries()]);
  const approvalKey = needsApproval(changes, anchor) ? changesKey : null;
  const setChangesNeedingApproval = useSetAtom(editChangesNeedingApprovalAtom);
  const setApproved = useSetAtom(editApprovedAtom);
  // Any change to the changes takes the approval back (editApprovedAtom).
  useGuardedEffect(
    () => {
      setChangesNeedingApproval(approvalKey);
      setApproved(false);
    },
    [approvalKey, setChangesNeedingApproval, setApproved],
    "EditMetadataControls:changesNeedingApproval"
  );
  const handleToggle = (index: number) => {
    const range = selectionRange(periods, toggleSelection(selected, index));
    setEditValidFrom(range?.validFrom ?? null);
    setEditValidTo(range && range.validTo !== "infinity" ? range.validTo : null);
  };
  // Tick all / Untick all for Change, as Remove has (owner 2026-11-16).
  // Unticking all clears the anchor: the next tick, or Tick all, sets it.
  const allTicked = periods.length > 0 && selected.length === periods.length;
  const tickAll = () => {
    if (allTicked) {
      setEditValidFrom(null);
      setEditValidTo(null);
      return;
    }
    const range = selectionRange(periods, periods.map((_, i) => i));
    setEditValidFrom(range?.validFrom ?? null);
    setEditValidTo(range && range.validTo !== "infinity" ? range.validTo : null);
  };

  // A record the unit does not have yet (no rows): its Timeline view is a
  // skeleton of the frames, cut to where the unit exists (the cap). The edit's
  // dates are the picked pieces; it starts on the Live piece, which starts
  // where the unit does when the unit was born inside Live (STATBUS-609).
  const existence = useUnitExistence(currentEdit.source);
  const empty = loaded && periods.length === 0;
  const pieces = empty && existence ? skeletonPieces(timeFrames, existence) : [];
  const picked = pieces.flatMap((p, i) =>
    p.available &&
    currentEdit.validFrom &&
    p.valid_from <= (currentEdit.validTo ?? "9999-12-31") &&
    (p.valid_to === "infinity" || p.valid_to >= currentEdit.validFrom)
      ? [i]
      : []
  );
  const handlePick = (index: number) => {
    const range = skeletonSelectionRange(pieces, toggleSelection(picked, index));
    setEditValidFrom(range?.validFrom ?? null);
    setEditValidTo(range && range.validTo !== "infinity" ? range.validTo : null);
  };

  // Edit opens in the Timeline view when the edit's frame holds more than one
  // value of the field (opensInTimeline); one value covering the frame opens
  // the Frame view. Decided once per edit, when its dates and rows are known.
  const openedRef = useRef(false);
  const datesKnown = !!currentEdit.validFrom;
  useGuardedEffect(
    () => {
      if (openedRef.current || !loaded || !datesKnown) return;
      openedRef.current = true;
      const frame = timeFrames.find((tf) => tf.ident === currentEdit.frameIdent);
      if (opensInTimeline(periods, frame)) setEditView("timeline");
    },
    [loaded, datesKnown],
    "EditMetadataControls:openInTimeline"
  );

  // A first value starts no earlier than the unit: the edit's opening dates
  // (the frame's) are capped to the unit's existence once it is read.
  const cappedRef = useRef(false);
  useGuardedEffect(
    () => {
      if (cappedRef.current || !empty || !existence || !currentEdit.validFrom) return;
      cappedRef.current = true;
      const capped = capToExistence(existence, currentEdit.validFrom, currentEdit.validTo ?? null);
      if (capped && capped.validFrom !== currentEdit.validFrom) setEditValidFrom(capped.validFrom);
    },
    [empty, existence, datesKnown],
    "EditMetadataControls:capFirstValueToUnit"
  );

  // Changing view keeps Change or Remove (owner 2026-11-13). Removing, the
  // Timeline starts with the pieces inside the Frame view's frame or dates
  // ticked; back in the Frame view the ticks are dropped and its own frame or
  // dates show again.
  const { pieces: removalPieces } = useRemovalPieces(currentEdit.source);
  const frameRemoval = useFrameRemovalPeriod();
  const handleModeChange = (next: TimeFramePanelMode) =>
    setEditView(
      next,
      next === "timeline" && frameRemoval.validFrom
        ? piecesInPeriod(removalPieces, frameRemoval.validFrom, frameRemoval.validTo)
        : undefined
    );
  const removing = currentEdit.removing != null;
  const canRemove = isRemovable(currentEdit.source) && loaded && periods.length > 0;
  const tickAllPeriods =
    !removing && mode === "timeline" && periods.length > 1 ? (
      <TickAllPeriods all={allTicked} onClick={tickAll} />
    ) : null;
  // Change | Remove, on the panel's heading line (owner 2026-11-13), for both
  // views: in the Frame view Remove takes out the chosen frame or dates; in
  // the Timeline the timeline splits into pieces per frame to tick.
  const changeRemoveSwitch = canRemove ? (
    <>
      {removing && mode === "timeline" && <TickAllPieces />}
      {tickAllPeriods}
      <div
        role="radiogroup"
        aria-label="Change or remove"
        className="inline-flex rounded-md border border-zinc-200 bg-zinc-100 p-0.5 text-xs"
        data-change-remove-switch=""
      >
        {([
          ["change", "Change"],
          ["remove", "Remove"],
        ] as const).map(([value, label]) => {
          const on = (value === "remove") === removing;
          return (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={on}
              data-change-remove={value}
              onClick={() =>
                !on &&
                setEditRemoving(
                  value === "remove"
                    ? mode === "timeline" && frameRemoval.validFrom
                      ? piecesInPeriod(removalPieces, frameRemoval.validFrom, frameRemoval.validTo)
                      : []
                    : null
                )
              }
              className={cn(
                "rounded px-2 py-0.5 text-zinc-600 transition-colors",
                on && value === "remove" && "bg-red-700 font-medium text-white shadow-sm",
                on && value === "change" && "bg-white font-medium text-zinc-900 shadow-sm",
                !on && "hover:text-zinc-900"
              )}
            >
              {label}
            </button>
          );
        })}
      </div>
    </>
  ) : undefined;
  // Back to a frame: the frame's dates come back.
  const handleChoiceChange = (next: ValidityChoice) => {
    if (next === "source_dates") return;
    setEditValidityChoice(next);
    if (next === "frame" && currentEdit.frameIdent) void changeEditFrame(currentEdit.frameIdent);
  };

  const dataSourceCode = dataSources.find((d) => String(d.id) === currentEdit.dataSourceId)?.code ?? null;

  // Every save of this edit goes through its form's submit, whichever button
  // starts it. A save reaching into a relative or fixed frame is held and the
  // user is asked (useFixedFrameConfirmation); Confirm submits again, marked
  // confirmed so it passes; Cancel stores nothing.
  const { ask, dialog } = useFixedFrameConfirmation();
  const confirmedRef = useRef(false);
  // A save waiting for approval is not sent, however it is started (Enter in
  // a field submits too); Save itself is disabled meanwhile (SaveApproval).
  const { blocked } = useSaveApproval();
  // What the save writes, period by period, for the past-frame question: the
  // same strikeouts the timeline shows (owner 2026-11-16).
  const changeList =
    changes.size > 0 ? (
      <ul className="space-y-1 rounded border border-zinc-200 p-2 text-zinc-900" data-save-changes="">
        {[...changes.entries()].map(([index, change]) => {
          const p = periods[index];
          return (
            <li key={p.valid_from} data-save-change={p.valid_from}>
              <div className="text-xs text-zinc-500">
                {p.valid_from} – {p.valid_to === "infinity" ? "Present" : p.valid_to}
                {change.dataSource && <ChangedSource change={change.dataSource} />}
              </div>
              {change.columns.length > 0 && <PeriodChangeView period={p} change={change} />}
            </li>
          );
        })}
      </ul>
    ) : null;
  // A date outside the unit's existence (dateOutsideBounds) holds the save: the
  // field already says why, so nothing is sent.
  const dateBounds =
    existence?.length ? { from: existence[0].validFrom, to: existence[existence.length - 1].validTo } : undefined;
  const boundsFrom = dateBounds?.from;
  const boundsTo = dateBounds?.to;
  useGuardedEffect(
    () => {
      const form = anchorRef.current?.closest("form");
      if (!form) return;
      const bounds = boundsFrom && boundsTo ? { from: boundsFrom, to: boundsTo } : undefined;
      const onSubmit = (event: SubmitEvent) => {
        const data = new FormData(form);
        const from = data.get("valid_from") as string | null;
        const to = data.get("valid_to") as string | null;
        if (dateOutsideBounds(from, bounds) || dateOutsideBounds(to, bounds) || blocked) {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
        if (confirmedRef.current) {
          confirmedRef.current = false;
          return;
        }
        // The period submitted is the form's own valid_from/valid_to fields.
        const held = ask(
          from,
          to,
          () => {
            confirmedRef.current = true;
            form.requestSubmit();
          },
          changeList
        );
        if (held) {
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      };
      form.addEventListener("submit", onSubmit, { capture: true });
      return () => form.removeEventListener("submit", onSubmit, { capture: true });
    },
    // Re-attached when the approval or the changes change, so the listener
    // holds the current ones (changesKey stands for changeList).
    [ask, boundsFrom, boundsTo, blocked, changesKey],
    "EditMetadataControls:askBeforeFixedFrameSave"
  );

  return (
    <>
      <Separator className="mt-1" />
      <div ref={anchorRef} hidden />
      {dialog}
      <TimeFramePanel
        idPrefix={fieldId}
        timeFrames={timeFrames}
        mode={mode}
        onModeChange={handleModeChange}
        choice={choice}
        onChoiceChange={handleChoiceChange}
        frameIdent={currentEdit.frameIdent ?? null}
        onFrameChange={(ident) => void changeEditFrame(ident)}
        validFrom={currentEdit.validFrom ?? null}
        validTo={currentEdit.validTo ?? null}
        onValidFromChange={(d) => setEditValidFrom(d)}
        onValidToChange={(d) => setEditValidTo(d === "infinity" ? null : d)}
        dataSources={dataSources}
        dataSourceCode={dataSourceCode}
        onDataSourceChange={(code) =>
          setEditDataSourceId(dataSources.find((d) => d.code === code)?.id?.toString() ?? null)
        }
        comment={currentEdit.editComment ?? null}
        onCommentChange={setEditComment}
        formFields
        dateBounds={dateBounds}
        headerControls={changeRemoveSwitch ?? tickAllPeriods ?? undefined}
        hideMetadata={removing}
        frameFooter={removing ? <FrameRemovalSummary /> : undefined}
        timeline={
          removing ? (
            <RemovalTimeline />
          ) : empty && pieces.length > 0 ? (
            <div className="space-y-1" data-edit-timeline="skeleton">
              <TimelineSkeleton
                pieces={pieces}
                picked={picked}
                onToggle={handlePick}
                unitStart={existence?.[0]?.validFrom}
              />
              <p className="text-xs text-zinc-600" data-edit-timeline-range="">
                {currentEdit.validFrom
                  ? `Fills ${currentEdit.validFrom} – ${currentEdit.validTo ?? "Present"}`
                  : "Tick the periods to fill"}
              </p>
            </div>
          ) : currentEdit.source && loaded && periods.length > 0 ? (
            <div className="space-y-1" data-edit-timeline="">
              <FieldTimeline
                periods={periods}
                selected={selected}
                onToggle={handleToggle}
                changes={removing ? undefined : changes}
                baseline={!removing && anchor >= 0 && anchor !== shown ? anchor : undefined}
              />
              <p className="text-xs text-zinc-600" data-edit-timeline-range="">
                {currentEdit.validFrom
                  ? `Changes ${currentEdit.validFrom} – ${currentEdit.validTo ?? "Present"}`
                  : "Tick the periods to change"}
              </p>
            </div>
          ) : undefined
        }
      />
    </>
  );
}

/**
 * Whether the open edit's Save waits for the user's approval: the save changes
 * a ticked period other than the one the form shows, and the user has not
 * approved exactly these changes (owner 2026-11-16).
 */
export function useSaveApproval() {
  const pending = useAtomValue(editChangesNeedingApprovalAtom);
  const [approved, setApproved] = useAtom(editApprovedAtom);
  return {
    needed: pending != null,
    approved: pending != null && approved,
    blocked: pending != null && !approved,
    approve: (on: boolean) => setApproved(on),
  };
}

/**
 * The approval left of Cancel when Save would change ticked periods besides
 * the anchor: the timeline highlights those changes, and Save stays disabled
 * until the user approves them here (owner 2026-11-16). Any change to the
 * ticks or the values afterwards takes the approval back.
 */
export function SaveApproval() {
  const { needed, approved, approve } = useSaveApproval();
  if (!needed) return null;
  return (
    <label
      className="mr-auto flex cursor-pointer items-center gap-2 text-sm text-zinc-800"
      data-save-approval={approved ? "approved" : "pending"}
    >
      <Checkbox
        checked={approved}
        onCheckedChange={(on) => approve(on === true)}
        aria-label="Approve timeline changes"
      />
      Approve timeline changes
    </label>
  );
}

/** Tick all / Untick all the Change timeline's periods, beside Change | Remove. */
function TickAllPeriods({ all, onClick }: { all: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="text-xs text-zinc-700 underline-offset-2 hover:underline"
      data-change-tick-all={all ? "clear" : "all"}
    >
      {all ? "Untick all" : "Tick all"}
    </button>
  );
}
