import React from "react";
import Link from "next/link";
import { Check, X } from "lucide-react";
import { createSupabaseSSRClient } from "@/utils/supabase/server";

export default async function OnboardingCompletedPage() {
  const client = await createSupabaseSSRClient();
  const { data: settings } = await client
    .from("settings")
    .select("activity_category_standard(id,name)")
    .limit(1);

  const { count: numberOfRegions } = await client
    .from("region")
    .select("id", { count: "exact" })
    .limit(0);

  const { count: numberOfLegalUnits } = await client
    .from("legal_unit")
    .select("id", { count: "exact" })
    .limit(0);

  const { count: numberOfEstablishments } = await client
    .from("establishment")
    .select("id", { count: "exact" })
    .limit(0);

  return (
    <div className="space-y-8">
      <h1 className="text-center text-2xl">Summary</h1>
      <p className="leading-loose">
        The following steps needs to be complete in order to have a fully
        functional Statbus. If you have not completed some of the steps, you can
        click the links to complete the steps.
      </p>

      <div className="space-y-6">
        <SummaryBlock
          success={!!settings?.[0]?.activity_category_standard}
          successText={`You have configured Statbus to use the activity category standard ${settings?.[0]?.activity_category_standard?.name}.`}
          failureText={
            "You have not configured Statbus to use an activity category standard"
          }
          failureLink={"/getting-started/activity-standard"}
        />

        <SummaryBlock
          success={!!numberOfRegions}
          successText={`You have uploaded ${numberOfRegions} regions.`}
          failureText="You have not uploaded any regions"
          failureLink={"/getting-started/upload-regions"}
        />

        <SummaryBlock
          success={!!numberOfLegalUnits}
          successText={`You have uploaded ${numberOfLegalUnits} legal units.`}
          failureText="You have not uploaded any legal units"
          failureLink={"/getting-started/upload-legal-units"}
        />

        <SummaryBlock
          success={!!numberOfEstablishments}
          successText={`You have uploaded ${numberOfEstablishments} establishments.`}
          failureText="You have not uploaded any establishments"
          failureLink={"/getting-started/upload-establishments"}
        />
      </div>

      {!!settings?.[0]?.activity_category_standard &&
      numberOfRegions &&
      numberOfLegalUnits ? (
        <div className="text-center">
          <Link className="underline" href="/">
            Start using Statbus
          </Link>
        </div>
      ) : null}
    </div>
  );
}

const SummaryBlock = ({
  success,
  successText,
  failureText,
  failureLink,
}: {
  success: boolean;
  successText: string;
  failureText: string;
  failureLink: string;
}) => {
  return (
    <div className="flex items-center space-x-6">
      <div>{success ? <Check /> : <X />}</div>
      <p>
        {success ? (
          successText
        ) : (
          <Link className="underline" href={failureLink}>
            {failureText}
          </Link>
        )}
      </p>
    </div>
  );
};
