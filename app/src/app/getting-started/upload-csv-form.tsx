"use client";

import { useFormState, useFormStatus } from "react-dom";
import { Button, buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import Link from "next/link";
import React, { useEffect } from "react";
import { ErrorBox } from "@/components/error-box";
import { uploadFile } from "@/app/getting-started/getting-started-actions";
import type { UploadView } from "@/app/getting-started/getting-started-actions";
import { useRouter } from "next/navigation";

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
}: {
  uploadView: UploadView;
  nextPage: string;
}) => {
  const filename = "upload-file";
  const [state, formAction] = useFormState(
    uploadFile.bind(null, filename, uploadView),
    { error: null }
  );
  const router = useRouter();

  useEffect(() => {
    if (state.success) {
      router.push(nextPage);
    }
  }, [state.success, router, nextPage]);

  return (
    <form action={formAction} className="bg-gray-50 p-6">
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
        className="mb-4"
      />
      <UploadFormButtons error={state.error} nextPage={nextPage} />
    </form>
  );
};
