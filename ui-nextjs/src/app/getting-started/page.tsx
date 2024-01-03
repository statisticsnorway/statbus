import {createClient} from "@/app/auth/_lib/supabase.server.client";
import React from "react";
import Link from "next/link";

export default async function Home() {
  const client = createClient()

  const {data: standards} = await client.from('activity_category_standard')
    .select('id, name')

  return (
    <div className="text-center">
      <h1 className="mb-6 font-medium text-lg">Welcome!</h1>
      <p className="mb-6">
        In this onboarding guide we will try to help you get going with Statbus.
        We will assist you in selecting an activity standard and you will get
        to upload your first region data set.
      </p>

      <Link className="underline" href="/getting-started/activity-standard">Start</Link>
    </div>
  )
}
