'use client';

import {useFormState, useFormStatus} from "react-dom";
import {Button, buttonVariants} from "@/components/ui/button";
import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import Link from "next/link";
import React from "react";
import {ErrorBox} from "@/components/error-box";
import {uploadFile} from "@/app/getting-started/getting-started-actions";
import type {UploadView} from "@/app/getting-started/getting-started-actions";

const UploadFormButtons = ({error, nextPage}: { error: string | null, nextPage: string }) => {
    const {pending} = useFormStatus();
    return (
        <>
            {
                !pending && error ? (
                    <ErrorBox>
                        <span className="text-sm">Failed to upload file: {error}</span>
                    </ErrorBox>
                ) : null
            }
            <div className="space-x-3">
                <Button disabled={pending} type="submit">Upload</Button>
                <Link href={nextPage} className={buttonVariants({variant: 'outline'})}>Skip</Link>
            </div>
        </>
    )
}

export const UploadCSVForm = ({uploadView, nextPage}: { uploadView: UploadView, nextPage: string }) => {
    const filename = "upload-file"
    const [state, formAction] = useFormState(uploadFile.bind(null, filename, uploadView), {error: null})

    return (
        <form action={formAction} className="space-y-6 bg-green-100 p-6">
            <Label className="block" htmlFor={filename}>Select file:</Label>
            <Input required id={filename} type="file" name={filename}/>
            <UploadFormButtons error={state.error} nextPage={nextPage}/>
        </form>
    )
}