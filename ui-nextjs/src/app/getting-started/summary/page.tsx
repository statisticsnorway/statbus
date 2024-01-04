import
  React from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase.server.client";

export default async function OnboardingCompleted() {

  const client = createClient()
  const {data: settings} = await client.from('settings').select('id, activity_category_standard(id,name)')
  const {data: regions} = await client.from('region').select('id, name')

  return (
    <div className="text-center space-y-6">
      <h1 className="font-medium text-lg">Congratulations!</h1>
      <p>
        You&apos;ve successfully completed the onboarding process. You have configured
        Statbus to use the <strong>{settings?.[0].activity_category_standard?.name}</strong> activity category standard
        and you have uploaded <strong>{regions?.length ?? 0}</strong> regions.
      </p>

      <Link className="block underline" href="/">Start using Statbus</Link>
    </div>
  )
}
