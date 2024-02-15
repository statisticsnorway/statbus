'use client';

import {useFormState} from "react-dom";
import {Button, buttonVariants} from "@/components/ui/button";
import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import Link from "next/link";
import React from "react";
import {ErrorBox} from "@/components/error-box";
import {uploadFile} from "@/app/getting-started/getting-started-actions";
import type {UploadView} from "@/app/getting-started/getting-started-actions";

const initialState: { error: string | null } = {
  error: null
}

const filename = "establishments"
const uploadView: UploadView = "establishment_region_activity_category_stats_current"

export default function UploadEstablishmentsForm() {
  const [state, formAction] = useFormState(uploadFile.bind(null, filename, uploadView), initialState)

  return (
    <form action={formAction} className="space-y-6 bg-green-100 p-6">
      <Label className="block" htmlFor={filename}>Select file:</Label>
      <Input required id={filename} type="file" name={filename} />
      {
        state.error ? (
          <ErrorBox>
            <span>{state.error}</span>
          </ErrorBox>
        ) : null
      }
      <div className="space-x-3">
        <Button type="submit">Upload</Button>
        <Link href="/getting-started/summary" className={buttonVariants({variant: 'outline'})}>Skip</Link>
      </div>
    </form>
  )
}
