import React from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase.server.client";

export default async function OnboardingCompletedPage() {

    const client = createClient()
    const {data: settings} = await client.from('settings').select('id, activity_category_standard(id,name)')
    const {data: regions} = await client.from('region').select('id, name')

    return (
        <div className="text-center space-y-6">
            <h1 className="font-medium text-lg">Summary</h1>
            {
                settings?.length ? (
                    <p>
                        You have configured Statbus to use
                        the <strong>{settings?.[0]?.activity_category_standard?.name}</strong> activity category
                        standard. If you want to change the selected activity category standard, you can do so
                        <Link className="underline" href={"/getting-started/activity-standard"}>&nbsp;here</Link>
                    </p>
                ) : (
                    <p>
                        You have not configured Statbus to use an activity category standard. You can configure this
                        <Link className="underline" href={"/getting-started/activity-standard"}>&nbsp;here</Link>
                    </p>
                )
            }

            {
                regions?.length ? (
                    <p>
                        You have uploaded <strong>{regions?.length ?? 0}</strong> regions.
                    </p>
                ) : (
                    <p>
                        You have not uploaded any regions. You can upload regions
                        <Link className="underline" href={"/getting-started/upload-regions"}>&nbsp;here</Link>
                    </p>
                )
            }

            {
                settings?.length && regions?.length ? (
                    <Link className="block underline" href="/">Start using Statbus</Link>
                ) : null
            }
        </div>
    )
}
