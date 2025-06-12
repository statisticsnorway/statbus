"use client";

import React, { Suspense, useEffect, useState } from "react"; // Added useEffect, useState
import Link from "next/link";
import { Check, Minus, X } from "lucide-react";
import { useAtomValue } from 'jotai';
import {
  activityCategoryStandardSettingAtomAsync,
  numberOfRegionsAtomAsync,
  numberOfCustomActivityCodesAtomAsync,
  numberOfCustomSectorsAtomAsync,
  numberOfCustomLegalFormsAtomAsync,
  hasStatisticalUnitsAtom, // To check if units have been imported
} from '@/atoms';
import { Loader2 } from 'lucide-react';

const SummaryContent = () => {
  const [isMounted, setIsMounted] = useState(false);
  useEffect(() => {
    setIsMounted(true);
  }, []);

  const activity_category_standard = useAtomValue(activityCategoryStandardSettingAtomAsync);
  const numberOfRegions = useAtomValue(numberOfRegionsAtomAsync);
  const numberOfCustomSectors = useAtomValue(numberOfCustomSectorsAtomAsync);
  const numberOfCustomLegalForms = useAtomValue(numberOfCustomLegalFormsAtomAsync);
  const numberOfCustomActivityCategoryCodes = useAtomValue(numberOfCustomActivityCodesAtomAsync);
  const hasUnits = useAtomValue(hasStatisticalUnitsAtom); // From baseDataAtom

  if (!isMounted) {
    // Render nothing or a minimal consistent placeholder until mounted.
    // The outer Suspense fallback (SummarySkeleton) will be shown if atoms are pending.
    // This specific check is to avoid rendering SummaryBlocks before client mount.
    return null; 
  }

  return (
    <>
      <p className="leading-loose">
        The following steps need to be completed in order to have a fully
        functional Statbus. If you have not completed some of the steps, you can
        click the links to complete the steps.
      </p>

      <div className="space-y-6">
        <SummaryBlock
          success={!!activity_category_standard}
          required={true}
          successText={`You have configured Statbus to use the activity category standard ${activity_category_standard?.name ?? 'N/A'}.`}
          failureText="You have not configured Statbus to use an activity category standard"
          failureLink="/getting-started/activity-standard"
        />
        <SummaryBlock
          success={!!numberOfCustomActivityCategoryCodes && numberOfCustomActivityCategoryCodes > 0}
          successText={`You have uploaded ${numberOfCustomActivityCategoryCodes ?? 0} custom activity categories.`}
          failureText="You have not uploaded any custom activity categories"
          failureLink="/getting-started/upload-custom-activity-standard-codes"
        />
        <SummaryBlock
          success={!!numberOfRegions && numberOfRegions > 0}
          required={true}
          successText={`You have uploaded ${numberOfRegions ?? 0} regions.`}
          failureText="You have not uploaded any regions"
          failureLink="/getting-started/upload-regions"
        />
        <SummaryBlock
          success={!!numberOfCustomSectors && numberOfCustomSectors > 0}
          successText={`You have uploaded ${numberOfCustomSectors ?? 0} custom sectors.`}
          failureText="You have not uploaded any custom sectors"
          failureLink="/getting-started/upload-custom-sectors"
        />
        <SummaryBlock
          success={!!numberOfCustomLegalForms && numberOfCustomLegalForms > 0}
          successText={`You have uploaded ${numberOfCustomLegalForms ?? 0} custom legal forms.`}
          failureText="You have not uploaded any custom legal forms"
          failureLink="/getting-started/upload-custom-legal-forms"
        />
      </div>
      {activity_category_standard && (numberOfRegions ?? 0) > 0 ? (
        <div className="text-center">
          <Link className="underline" href={hasUnits ? "/" : "/import"}>
            {hasUnits ? "Go to Dashboard" : "Start importing units"}
          </Link>
        </div>
      ) : (
        <p className="text-center text-sm text-gray-600">
          Complete setting the activity standard and uploading regions to proceed.
        </p>
      )}
    </>
  );
};

const SummarySkeleton = () => (
  <div className="space-y-6">
    {[...Array(5)].map((_, i) => (
      <div key={i} className="flex items-center space-x-6 animate-pulse">
        <div className="h-6 w-6 bg-gray-200 rounded-full"></div>
        <div className="h-4 bg-gray-200 rounded w-3/4"></div>
      </div>
    ))}
    <div className="text-center mt-4">
      <div className="h-4 bg-gray-200 rounded w-1/4 mx-auto"></div>
    </div>
  </div>
);

export default function OnboardingCompletedPage() {
  return (
    <div className="space-y-8">
      <h1 className="text-center text-2xl">Summary</h1>
      <Suspense fallback={<SummarySkeleton />}>
        <SummaryContent />
      </Suspense>
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
