'use client';

import {useFormState} from "react-dom";
import {Button, buttonVariants} from "@/components/ui/button";
import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import Link from "next/link";
import React from "react";
import {ErrorBox} from "@/components/error-box";
import type {UploadView} from "@/app/getting-started/getting-started-actions";
import {uploadFile} from "@/app/getting-started/getting-started-actions";

const initialState: { error: string | null } = {
  error: null
}

const filename = "custom_activity_category_codes"
const uploadView: UploadView = "activity_category_available_custom"

export default function UploadCustomActivitiesForm() {
  const [state, formAction] = useFormState(uploadFile.bind(null, filename, uploadView), initialState)

  return (
    <form action={formAction} className="space-y-6 bg-green-100 p-6">
      <Label className="block" htmlFor="custom-activity-categories-file">Select Custom Activity Categories file:</Label>
      <Input required id="custom-activity-categories-file" type="file" name={filename}/>
      {
        state.error ? (
          <ErrorBox>
            <span className="text-sm">{state.error}</span>
          </ErrorBox>
        ) : null
      }
      <div className="space-x-3">
        <Button type="submit">Upload</Button>
        <Link href="/getting-started/upload-legal-units" className={buttonVariants({variant: 'outline'})}>Skip</Link>
      </div>
    </form>
  )
}
