"use client";

import React from "react";
import Link from "next/link";
import { Check, X } from "lucide-react";
import { useGettingStarted } from "../GettingStartedContext";
import { useBaseData } from "@/app/BaseDataClient";

export default function OnboardingCompletedPage() {
  const {
    activity_category_standard,
    numberOfRegions,
    numberOfLegalUnits,
    numberOfEstablishments,
  } = useGettingStarted();
  const { hasStatisticalUnits } = useBaseData();
  return (
    <div className="space-y-8">
      <h1 className="text-center text-2xl">Summary</h1>
      <p className="leading-loose">
        The following steps need to be completed in order to have a fully
        functional Statbus. If you have not completed some of the steps, you can
        click the links to complete the steps.
      </p>

      <div className="space-y-6">
        <SummaryBlock
          success={!!activity_category_standard}
          successText={`You have configured Statbus to use the activity category standard ${activity_category_standard?.name}.`}
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

      <SummaryBlock
        success={hasStatisticalUnits}
        successText="Analysis for Search and Reports completed."
        failureText="Statistical Units and Reports are not available"
        failureLink="/getting-started/refresh-statistical-units"
      />
      {!!activity_category_standard &&
        numberOfRegions &&
        numberOfLegalUnits &&
        hasStatisticalUnits ? (
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
