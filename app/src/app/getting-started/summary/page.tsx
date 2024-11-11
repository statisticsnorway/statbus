"use client";

import React from "react";
import Link from "next/link";
import { Check, Minus, X } from "lucide-react";
import { useGettingStarted } from "../GettingStartedContext";

export default function OnboardingCompletedPage() {
  const {
    activity_category_standard,
    numberOfRegions,
    numberOfCustomSectors,
    numberOfCustomLegalForms,
    numberOfCustomActivityCategoryCodes,
  } = useGettingStarted();

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
          required={true}
          successText={`You have configured Statbus to use the activity category standard ${activity_category_standard?.name}.`}
          failureText={
            "You have not configured Statbus to use an activity category standard"
          }
          failureLink={"/getting-started/activity-standard"}
        />
        <SummaryBlock
          success={!!numberOfRegions}
          required={true}
          successText={`You have uploaded ${numberOfRegions} regions.`}
          failureText="You have not uploaded any regions"
          failureLink={"/getting-started/upload-regions"}
        />
        <SummaryBlock
          success={!!numberOfCustomSectors}
          successText={`You have uploaded ${numberOfCustomSectors} custom sectors.`}
          failureText="You have not uploaded any custom sectors"
          failureLink={"/getting-started/upload-custom-sectors"}
        />
        <SummaryBlock
          success={!!numberOfCustomLegalForms}
          successText={`You have uploaded ${numberOfCustomLegalForms} custom legal forms.`}
          failureText="You have not uploaded any custom legal forms"
          failureLink={"/getting-started/upload-custom-legal-forms"}
        />
        <SummaryBlock
          success={!!numberOfCustomActivityCategoryCodes}
          successText={`You have uploaded ${numberOfCustomActivityCategoryCodes} custom activity categories.`}
          failureText="You have not uploaded any custom activity categories"
          failureLink={"/getting-started/upload-custom-activity-standard-codes"}
        />
      </div>
      {!!activity_category_standard && numberOfRegions ? (
        <div className="text-center">
          <Link className="underline" href="/import/legal-units">
            Start importing units
          </Link>
        </div>
      ) : null}
    </div>
  );
}

const SummaryBlock = ({
  success,
  required,
  successText,
  failureText,
  failureLink,
}: {
  success: boolean;
  required?: boolean;
  successText: string;
  failureText: string;
  failureLink: string;
}) => {
  return (
    <div className="flex items-center space-x-6">
      <div>{success ? <Check /> : required ? <X /> : <Minus />}</div>
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
