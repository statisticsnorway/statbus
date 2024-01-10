import React from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase.server.client";
import {AlertCircle, Check} from "lucide-react";

export default async function OnboardingCompletedPage() {
  const client = createClient()
  const {data: settings} = await client.from('settings').select('id, activity_category_standard(id,name)')
  const {data: regions} = await client.from('region').select('id, name')
  const {data: legalUnits} = await client.from('legal_unit').select('id, name')

  return (
    <div className="space-y-8">
      <h1 className="font-medium text-lg text-center">Summary</h1>


      <div className="flex items-center space-x-3">
        <div>
          {
            settings?.length ? <Check/> : <AlertCircle/>
          }
        </div>
        <p>
          {
            settings?.length ? (
              <>
                You have configured Statbus to use
                the <strong>{settings?.[0]?.activity_category_standard?.name}</strong> activity category
                standard.
              </>
            ) : (
              <>
                You have not configured Statbus to use an activity category standard. You can configure
                activity category standards&nbsp;
                <Link className="underline" href={"/getting-started/activity-standard"}>here</Link>
              </>
            )
          }
        </p>
      </div>

      <div className="flex items-center space-x-3">
        <div>
          {
            regions?.length ? <Check/> : <AlertCircle/>
          }
        </div>
        <p>
          {
            regions?.length ? (
              <>
                You have uploaded <strong>{regions.length}</strong> regions.
              </>
            ) : (
              <>
                You have not uploaded any regions. You can upload regions&nbsp;
                <Link className="underline" href={"/getting-started/upload-regions"}>   here</Link>
              </>
            )
          }
        </p>
      </div>

      <div className="flex items-center space-x-3">
        <div>
          {
            legalUnits?.length ? <Check/> : <AlertCircle/>
          }
        </div>
        <p>
          {
            legalUnits?.length ? (
              <>
                You have uploaded <strong>{legalUnits.length}</strong> legal units.
              </>
            ) : (
              <>
                You have not uploaded any legal units. You can do so&nbsp;
                <Link className="underline" href={"/getting-started/upload-regions"}>here</Link>
              </>
            )
          }
        </p>
      </div>

      {
        settings?.length && regions?.length && legalUnits?.length ? (
          <div className="text-center">
            <Link className="underline" href="/">Start using Statbus</Link>
          </div>
        ) : null
      }
    </div>
  )
}
