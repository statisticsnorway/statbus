import React from "react";
import {InfoBox} from "@/components/InfoBox";
import {createClient} from "@/lib/supabase/server";
import UploadCustomActivitiesForm from "@/app/getting-started/upload-custom-activity-standard-codes/UploadCustomActivitiesForm";

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
      <UploadCustomActivitiesForm/>
    </section>
  )
}