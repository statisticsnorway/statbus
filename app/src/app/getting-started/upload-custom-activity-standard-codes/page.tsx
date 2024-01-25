import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import {Button, buttonVariants} from "@/components/ui/button";
import React from "react";
import Link from "next/link";
import {InfoBox} from "@/components/InfoBox";
import {createClient} from "@/lib/supabase/server";
import {uploadCustomActivityCodes} from "@/app/getting-started/upload-custom-activity-standard-codes/actions";

export default async function UploadCustomActivityCategoryCodesPage() {
  const client = createClient()
  const {count} = await client.from('activity_category_available_custom').select('*', {count: 'exact', head: true})
  return (
    <section className="space-y-8">
      <h1 className="text-xl text-center">Upload Custom Activity Category Standard Codes</h1>
      <p>
        Upload a CSV file containing the custom activity category standard codes you want to use in your analysis.
      </p>

      {
        count && count > 0 ? (
          <InfoBox>
            <p>
              There are already {count} custom activity category codes defined.
            </p>
          </InfoBox>
        ) : null
      }

      <form action={uploadCustomActivityCodes} className="space-y-6 bg-green-100 p-6">
        <Label className="block" htmlFor="custom-activity-categories-file">Select Custom Activity Categories
          file:</Label>
        <Input required id="custom-activity-categories-file" type="file" name="custom_activity_category_codes"/>
        <div className="space-x-3">
          <Button type="submit">Upload</Button>
          <Link href="/getting-started/upload-legal-units" className={buttonVariants({variant: 'outline'})}>Skip</Link>
        </div>
      </form>
    </section>
  )
}
