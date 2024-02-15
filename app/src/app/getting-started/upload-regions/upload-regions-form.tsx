'use client';

import {useFormState} from "react-dom";
import {Button, buttonVariants} from "@/components/ui/button";
import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import Link from "next/link";
import React from "react";
import {ErrorBox} from "@/components/error-box";
import {uploadFile, UploadView} from "@/app/getting-started/getting-started-actions";

const initialState: { error: string | null } = {
  error: null
}

const filename = "regions"
const uploadView: UploadView = "region_upload"

export default function UploadRegionsForm() {
    const [state, formAction] = useFormState(uploadFile.bind(null, filename, uploadView), initialState)

  return (
    <form action={formAction} className="space-y-6 bg-green-100 p-6">
      <Label className="block" htmlFor="regions-file">Select regions file:</Label>
      <Input required id="regions-file" type="file" name={filename}/>
      {
        state.error ? (
          <ErrorBox>
            <span className="text-sm">{state.error}</span>
          </ErrorBox>
        ) : null
      }
      <div className="space-x-3">
        <Button type="submit">Upload</Button>
        <Link
          href="/getting-started/upload-custom-activity-standard-codes"
          className={buttonVariants({variant: 'outline'})}
        >Skip</Link>
      </div>
    </form>
  )
}
