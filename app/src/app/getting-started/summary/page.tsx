import React from "react";
import Link from "next/link";
import {Check, X} from "lucide-react";
import {createClient} from "@/lib/supabase/server";

export default async function OnboardingCompletedPage() {
    const client = createClient()
    const {data: settings, count: numberOfSettings} = await client.from('settings').select('activity_category_standard(id,name)', {count: 'exact'}).limit(1)
    const {count: numberOfRegions} = await client.from('region').select('id', {count: 'exact'}).limit(1)
    const {count: numberOfLegalUnits} = await client.from('legal_unit').select('id', {count: 'exact'}).limit(1)
    const {count: numberOfCustomActivityCategoryCodes} = await client.from('activity_category_available_custom').select('path', {count: 'exact'}).limit(1)

    return (
        <div className="space-y-8">
            <h1 className="font-medium text-lg text-center">Summary</h1>


            <div className="flex items-center space-x-3">
                <div>
                    {
                        numberOfSettings ? <Check/> : <X/>
                    }
                </div>
                <p>
                    {
                        numberOfSettings ? (
                            <>
                                You have configured StatBus to use
                                the <strong>{settings?.[0]?.activity_category_standard?.name}</strong> activity category
                                standard.
                            </>
                        ) : (
                            <>
                                You have not configured StatBus to use an activity category standard. You can configure
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
                        numberOfCustomActivityCategoryCodes ? <Check/> : <X/>
                    }
                </div>
                <p>
                    {
                        numberOfCustomActivityCategoryCodes ? (
                            <>
                                You have configured StatBus to use
                                the <strong>{numberOfCustomActivityCategoryCodes}</strong> custom activity category
                                codes.
                            </>
                        ) : (
                            <>
                                You have not configured StatBus to use any custom activity category codes. You can
                                configure
                                custom activity category standards&nbsp;
                                <Link className="underline"
                                      href={"/getting-started/upload-custom-activity-standard-codes"}>here</Link>
                            </>
                        )
                    }
                </p>
            </div>

            <div className="flex items-center space-x-3">
                <div>
                    {
                        numberOfRegions ? <Check/> : <X/>
                    }
                </div>
                <p>
                    {
                        numberOfRegions ? (
                            <>
                                You have uploaded <strong>{numberOfRegions}</strong> regions.
                            </>
                        ) : (
                            <>
                                You have not uploaded any regions. You can upload regions&nbsp;
                                <Link className="underline" href={"/getting-started/upload-regions"}> here</Link>
                            </>
                        )
                    }
                </p>
            </div>

            <div className="flex items-center space-x-3">
                <div>
                    {
                        numberOfLegalUnits ? <Check/> : <X/>
                    }
                </div>
                <p>
                    {
                        numberOfLegalUnits ? (
                            <>
                                You have uploaded <strong>{numberOfLegalUnits}</strong> legal units.
                            </>
                        ) : (
                            <>
                                You have not uploaded any legal units. You can do so&nbsp;
                                <Link className="underline" href={"/getting-started/upload-legal-units"}>here</Link>
                            </>
                        )
                    }
                </p>
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
