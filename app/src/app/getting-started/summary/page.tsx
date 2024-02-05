import React from "react";
import Link from "next/link";
import {Check, X} from "lucide-react";
import {createClient} from "@/lib/supabase/server";

export default async function OnboardingCompletedPage() {
  const client = createClient()
  const {data: settings, count: numberOfSettings} = await client
    .from('settings')
    .select('activity_category_standard(id,name)', {count: 'exact'})
    .limit(1)

  const {count: numberOfRegions} = await client
    .from('region')
    .select('id', {count: 'exact'})
    .limit(0)

  const {count: numberOfLegalUnits} = await client
    .from('legal_unit')
    .select('id', {count: 'exact'})
    .limit(0)

  const {count: numberOfCustomActivityCategoryCodes} = await client
    .from('activity_category_available_custom')
    .select('path', {count: 'exact'})
    .limit(0)

  return (
    <div className="space-y-12">
      <h1 className="font-medium text-lg text-center">Summary</h1>

      <div className="space-y-6">

        <SummaryBlock
          success={!!numberOfSettings}
          successText={`You have configured StatBus to use the activity category standard ${settings?.[0]?.activity_category_standard?.name}.`}
          failureText={"You have not configured StatBus to use an activity category standard."}
          failureLink={"/getting-started/activity-standard"}
        />

        <SummaryBlock
          success={!!numberOfCustomActivityCategoryCodes}
          successText={`You have configured StatBus to use ${numberOfCustomActivityCategoryCodes} custom activity category codes.`}
          failureText="You have not configured StatBus to use any custom activity category codes."
          failureLink={"/getting-started/upload-custom-activity-standard-codes"}
        />

        <SummaryBlock
          success={!!numberOfRegions}
          successText={`You have uploaded ${numberOfRegions} regions.`}
          failureText="You have not uploaded any regions."
          failureLink={"/getting-started/upload-regions"}
        />

        <SummaryBlock
          success={!!numberOfLegalUnits}
          successText={`You have uploaded ${numberOfLegalUnits} legal units.`}
          failureText="You have not uploaded any legal units."
          failureLink={"/getting-started/upload-legal-units"}
        />
      </div>

      {
        numberOfSettings && numberOfRegions && numberOfLegalUnits ? (
          <div className="text-center">
            <Link className="underline" href="/">Start using StatBus</Link>
          </div>
        ) : null
      }
    </div>
  )
}

const SummaryBlock = ({success, successText, failureText, failureLink}: {
  success: boolean,
  successText: string,
  failureText: string,
  failureLink: string
}) => {
  return (
    <div className="flex items-center space-x-6">
      <div>
        {
          success ? <Check/> : <X/>
        }
      </div>
      <p>
        {
          success ? successText : <Link className="underline" href={failureLink}>{failureText}</Link>
        }
      </p>
    </div>
  )
}
