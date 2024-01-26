'use client';

import {uploadLegalUnits} from "@/app/getting-started/upload-legal-units/actions";
import {useFormState} from "react-dom";
import {Button, buttonVariants} from "@/components/ui/button";
import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import Link from "next/link";
import React from "react";
import {AlertCircle} from "lucide-react";

const initialState: { error: string | null } = {
  error: null
}

export default function UploadLegalUnitsForm() {
  const [state, formAction] = useFormState(uploadLegalUnits, initialState)

  return (
    <form action={formAction} className="space-y-6 bg-green-100 p-6">
      <Label className="block" htmlFor="legal-units-file">Select Legal Units file:</Label>
      <Input required id="legal-units-file" type="file" name="legal_units"/>
      {
        state.error ? (
          <div className="text-sm flex space-x-4 items-center p-3 bg-red-100">
            <div>
              <AlertCircle size={32} color="red"/>
            </div>
            <span className="text-red-500 font-semibold">{state.error}</span>
          </div>
        ) : null
      }
      <div className="space-x-3">
        <Button type="submit">Upload</Button>
        <Link href="/getting-started/summary" className={buttonVariants({variant: 'outline'})}>Skip</Link>
      </div>
    </form>
  )
}
