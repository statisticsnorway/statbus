'use client';

import {useFormState} from "react-dom";
import {Button, buttonVariants} from "@/components/ui/button";
import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import Link from "next/link";
import React from "react";
import {ErrorBox} from "@/components/error-box";
import {uploadCustomActivityCodes} from "@/app/getting-started/getting-started-actions";

const initialState: { error: string | null } = {
  error: null
}

export default function UploadCustomActivitiesForm() {
  const [state, formAction] = useFormState(uploadCustomActivityCodes, initialState)

  return (
    <form action={formAction} className="space-y-6 bg-green-100 p-6">
      <Label className="block" htmlFor="custom-activity-categories-file">Select Custom Activity Categories file:</Label>
      <Input required id="custom-activity-categories-file" type="file" name="custom_activity_category_codes"/>
      {
        state.error ? (
          <ErrorBox>
            <span>{state.error}</span>
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
