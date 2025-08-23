"use client";

import { useFormStatus } from "react-dom";
import { Button, buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import Link from "next/link";
import React, { useEffect, useActionState } from "react";
import { ErrorBox } from "@/components/error-box";
import { uploadFile } from "@/app/getting-started/getting-started-server-actions";
import type { UploadView } from "@/app/getting-started/getting-started-server-actions";
import { useRouter } from "next/navigation";
import { useSetAtom } from "jotai";
import { pendingRedirectAtom } from "@/atoms/app";

const UploadFormButtons = ({
  error,
  nextPage,
}: {
  error: string | null;
  nextPage: string;
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
        <Button disabled={pending} type="submit">
          Upload
        </Button>
        <Link
          href={nextPage}
          className={buttonVariants({ variant: "outline" })}
        >
          Skip
        </Link>
      </div>
    </div>
  );
};

export const UploadCSVForm = ({
  uploadView,
  nextPage,
  refreshRelevantCounts,
}: {
  uploadView: UploadView;
  nextPage: string;
  refreshRelevantCounts: () => Promise<void>;
}) => {
  const filename = "upload-file";
  const [state, formAction] = useActionState(
    uploadFile.bind(null, filename, uploadView),
    { error: null }
  );
  const router = useRouter();
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);

  useEffect(() => {
    if (state.success) {
      setPendingRedirect(nextPage);
      refreshRelevantCounts();
    }
  }, [state.success, setPendingRedirect, nextPage, refreshRelevantCounts]);

  return (
    <form action={formAction} className="bg-ssb-light p-6">
      <Label
        className="block mb-4 ml-1 text-sm font-semibold"
        htmlFor={filename}
      >
        Select file
      </Label>
      <Input
        required
        id={filename}
        type="file"
        name={filename}
        accept=".csv"
        className="mb-4"
      />
      <UploadFormButtons error={state.error} nextPage={nextPage} />
    </form>
  );
};
