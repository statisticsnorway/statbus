"use client";

import { useFormStatus } from "react-dom";
import { Button, buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import Link from "next/link";
import React, { useActionState, useRef, useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { ErrorBox } from "@/components/error-box";
import { uploadFile } from "@/app/getting-started/getting-started-server-actions";
import type { UploadView } from "@/app/getting-started/getting-started-server-actions";
import { useRouter } from "next/navigation";
import { fileAsCsvText, isExcelFile } from "./upload-excel";
import { Loader2 } from "lucide-react";

/** Stores the checked file; disabled, with a spinner, while it is being stored. */
const StoreButton = () => {
  const { pending } = useFormStatus();
  return (
    <Button disabled={pending} type="submit" data-upload-submit="">
      {pending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
      {pending ? "Storing…" : "Store"}
    </Button>
  );
};

const UploadFormButtons = ({
  error,
  nextPage,
  label,
}: {
  error: string | null;
  nextPage: string;
  label: string;
}) => {
  const { pending } = useFormStatus();
  return (
    <div className="space-y-3">
      {!pending && error ? (
        <ErrorBox>
          <span className="text-sm">Failed to upload file: {error}</span>
        </ErrorBox>
      ) : null}
      <div className="space-x-3">
        <Button disabled={pending} type="submit" data-upload-submit="">
          {label}
        </Button>
        <Link href={nextPage} className={buttonVariants({ variant: "outline" })}>
          Skip
        </Link>
      </div>
    </div>
  );
};

/**
 * A check of a chosen file before it is stored: given the file as CSV text, it shows what the
 * upload would do and whether there is anything to store (5yxn4w, the Regions upload). `canStore`
 * is false for a file with errors and for one that changes nothing.
 */
export type UploadPreview = (csv: string) => Promise<{ summary: React.ReactNode; canStore: boolean }>;

/**
 * The getting-started upload of a CSV or Excel file (owner 2026-11-26: everybody uses Excel). An
 * Excel workbook's first sheet is read in the browser and sent as CSV, so the upload views and the
 * server's checks (upload-csv-check.ts) see one format. With `preview`, Upload first shows what
 * the file would do; nothing is stored until Store is pressed.
 */
export const UploadCSVForm = ({
  uploadView,
  nextPage,
  refreshRelevantCounts,
  preview,
}: {
  uploadView: UploadView;
  nextPage: string;
  refreshRelevantCounts: () => Promise<void>;
  preview?: UploadPreview;
}) => {
  const filename = "upload-file";
  const [state, formAction] = useActionState(
    uploadFile.bind(null, filename, uploadView),
    { error: null }
  );
  const router = useRouter();
  const fileInput = useRef<HTMLInputElement>(null);
  // The checked file, as CSV, while its summary is shown and the person decides.
  const [checked, setChecked] = useState<{ name: string; csv: string; summary: React.ReactNode; canStore: boolean } | null>(null);
  const [readError, setReadError] = useState<string | null>(null);
  const [reading, setReading] = useState(false);

  useGuardedEffect(() => {
    if (state.success) {
      router.push(nextPage);
      refreshRelevantCounts();
    }
  }, [state.success, router, nextPage, refreshRelevantCounts], 'UploadCSVForm:redirectOnSuccess');

  // The file as the server action takes it: CSV, whatever was chosen.
  const asCsvFile = (name: string, csv: string) =>
    new File([csv], name.replace(/\.(xlsx|xls)$/i, ".csv"), { type: "text/csv" });

  const submit = async (formData: FormData) => {
    setReadError(null);
    if (checked) {
      const data = new FormData();
      data.set(filename, asCsvFile(checked.name, checked.csv));
      formAction(data);
      return;
    }
    const file = formData.get(filename);
    if (!(file instanceof File) || (file.size === 0 && !file.name)) {
      formAction(formData);
      return;
    }
    if (!isExcelFile(file)) {
      formAction(formData);
      return;
    }
    setReading(true);
    try {
      const data = new FormData();
      data.set(filename, asCsvFile(file.name, await fileAsCsvText(file)));
      formAction(data);
    } catch (e) {
      setReadError(`${file.name} could not be read: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setReading(false);
    }
  };

  // With a check, a chosen file is checked at once (owner 2026-11-26): what it would do shows as
  // soon as it is picked, and Store is the one step left.
  const check = async (file: File | undefined) => {
    setReadError(null);
    setChecked(null);
    if (!preview || !file) return;
    setReading(true);
    try {
      const csv = await fileAsCsvText(file);
      const { summary, canStore } = await preview(csv);
      setChecked({ name: file.name, csv, summary, canStore });
    } catch (e) {
      setReadError(`${file.name} could not be read: ${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setReading(false);
    }
  };

  // Cancel drops the picked file and its check, back to the empty form.
  const cancel = () => {
    setChecked(null);
    setReadError(null);
    if (fileInput.current) fileInput.current.value = "";
  };
  const picked = checked !== null || readError !== null;

  return (
    <form action={submit} className="bg-ssb-light p-6" data-upload-form={uploadView}>
      <Label
        className="block mb-4 ml-1 text-sm font-semibold"
        htmlFor={filename}
      >
        Select a CSV or Excel file
      </Label>
      <Input
        ref={fileInput}
        required={!checked}
        id={filename}
        type="file"
        name={filename}
        accept=".csv,.xlsx,.xls"
        className="mb-4 bg-white"
        onChange={(e) => void check(e.target.files?.[0])}
        disabled={reading}
      />
      {reading && preview && <p className="mb-4 text-sm text-gray-600">Checking the file…</p>}
      {readError && (
        <ErrorBox>
          <span className="text-sm">{readError}</span>
        </ErrorBox>
      )}
      {checked && (
        <div className="mb-4 rounded border bg-white p-4 text-sm" data-upload-preview="">
          <p className="mb-2 font-medium">What {checked.name} would do</p>
          {checked.summary}
        </div>
      )}
      {preview ? (
        // The picker stays open (owner 2026-11-26): another file is checked at once in its place.
        // With a picked file the choice is Store or Cancel, Store only when there is something to
        // store; before a file is picked, Skip goes on without one.
        <div className="space-y-3">
          {state.error && (
            <ErrorBox>
              <span className="text-sm">Failed to upload file: {state.error}</span>
            </ErrorBox>
          )}
          <div className="space-x-3">
            {checked?.canStore && <StoreButton />}
            {picked ? (
              <Button type="button" variant="outline" onClick={cancel} disabled={reading}>
                Cancel
              </Button>
            ) : (
              <Link href={nextPage} className={buttonVariants({ variant: "outline" })}>
                Skip
              </Link>
            )}
          </div>
        </div>
      ) : (
        <UploadFormButtons
          error={state.error}
          nextPage={nextPage}
          label={reading ? "Reading the file…" : "Upload"}
        />
      )}
    </form>
  );
};
