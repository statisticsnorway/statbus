"use client";
"use client";
import React, { Suspense, useState } from 'react'; // Added useEffect, useState
import { useGuardedEffect } from '@/hooks/use-guarded-effect';
import { useAtomValue } from 'jotai';
import {
  activityCategoryStandardSettingAtomAsync,
  numberOfCustomActivityCodesAtomAsync,
  numberOfCustomLegalFormsAtomAsync,
  numberOfCustomSectorsAtomAsync,
  numberOfRegionsAtomAsync,
} from '@/atoms/getting-started';
import { NavItem } from "@/app/getting-started/@progress/nav-item";
import { Loader2 } from 'lucide-react';

const ProgressStatusContent = () => {
  const [isMounted, setIsMounted] = useState(false);
  useGuardedEffect(() => {
    setIsMounted(true);
  }, [], 'GettingStartedProgress:setMounted');

  const activity_category_standard = useAtomValue(activityCategoryStandardSettingAtomAsync);
  const numberOfRegions = useAtomValue(numberOfRegionsAtomAsync);
  const numberOfCustomActivityCategoryCodes = useAtomValue(numberOfCustomActivityCodesAtomAsync);
  const numberOfCustomSectors = useAtomValue(numberOfCustomSectorsAtomAsync);
  const numberOfCustomLegalForms = useAtomValue(numberOfCustomLegalFormsAtomAsync);

  if (!isMounted) {
    // Render nothing or a minimal consistent placeholder until mounted.
    // The outer Suspense fallback (ProgressSkeleton) will be shown if atoms are pending.
    return null;
  }

  return (
    <ul className="text-sm">
      <li className="mb-6">
        <NavItem
          done={!!activity_category_standard}
          title="1. Set Activity Category Standard"
          href="/getting-started/activity-standard"
          subtitle={activity_category_standard?.name ?? undefined}
        />
      </li>
      <li className="mb-6">
        <NavItem
          done={!!numberOfCustomActivityCategoryCodes && numberOfCustomActivityCategoryCodes > 0}
          title="2. Upload Custom Activity Category Standard Codes (optional)"
          href="/getting-started/upload-custom-activity-standard-codes"
          subtitle={`${numberOfCustomActivityCategoryCodes ?? 0} custom activity category codes uploaded`}
        />
      </li>
      <li className="mb-6">
        <NavItem
          done={!!numberOfRegions && numberOfRegions > 0}
          title="3. Upload Region Hierarchy"
          href="/getting-started/upload-regions"
          subtitle={`${numberOfRegions ?? 0} regions uploaded`}
        />
      </li>
      <li className="mb-6">
        <NavItem
          done={!!numberOfCustomSectors && numberOfCustomSectors > 0}
          title="4. Upload Custom Sectors (optional)"
          href="/getting-started/upload-custom-sectors"
          subtitle={`${numberOfCustomSectors ?? 0} custom sectors uploaded`}
        />
      </li>
      <li className="mb-6">
        <NavItem
          done={!!numberOfCustomLegalForms && numberOfCustomLegalForms > 0}
          title="5. Upload Custom Legal Forms (optional)"
          href="/getting-started/upload-custom-legal-forms"
          subtitle={`${numberOfCustomLegalForms ?? 0} custom legal forms codes uploaded`}
        />
      </li>
      <li>
        <NavItem title="6. Summary" href="/getting-started/summary" />
      </li>
    </ul>
  );
};

const ProgressSkeleton = () => (
  <div className="space-y-4">
    {[...Array(6)].map((_, i) => (
      <div key={i} className="animate-pulse">
        <div className="h-4 bg-gray-200 rounded w-3/4 mb-1"></div>
        <div className="h-3 bg-gray-200 rounded w-1/2"></div>
      </div>
    ))}
  </div>
);

export default function SetupStatus() {
  return (
    <nav>
      <h2 className="text-2xl font-normal mb-12 text-center">
        Steps to get started
      </h2>
      <Suspense fallback={<ProgressSkeleton />}>
        <ProgressStatusContent />
      </Suspense>
    </nav>
  );
}
