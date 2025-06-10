"use client";
import { useGettingStartedManager as useGettingStarted } from '@/atoms/hooks';
import { NavItem } from "@/app/getting-started/@progress/nav-item";

export default function SetupStatus() {
  const { dataState } = useGettingStarted();
  const {
    activity_category_standard,
    numberOfRegions,
    numberOfCustomActivityCategoryCodes,
    numberOfCustomSectors,
    numberOfCustomLegalForms,
  } = dataState;

  return (
    <nav>
      <h2 className="text-2xl font-normal mb-12 text-center">
        Steps to get started
      </h2>
      <ul className="text-sm">
        <li className="mb-6">
          <NavItem
            done={!!activity_category_standard}
            title="1. Set Activity Category Standard"
            href="/getting-started/activity-standard"
            subtitle={activity_category_standard?.name}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfCustomActivityCategoryCodes}
            title="2. Upload Custom Activity Category Standard Codes (optional)"
            href="/getting-started/upload-custom-activity-standard-codes"
            subtitle={`${numberOfCustomActivityCategoryCodes} custom activity category codes uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfRegions}
            title="3. Upload Region Hierarchy"
            href="/getting-started/upload-regions"
            subtitle={`${numberOfRegions} regions uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfCustomSectors}
            title="4. Upload Custom Sectors (optional)"
            href="/getting-started/upload-custom-sectors"
            subtitle={`${numberOfCustomSectors} custom sectors uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfCustomLegalForms}
            title="5. Upload Custom Legal Forms (optional)"
            href="/getting-started/upload-custom-legal-forms"
            subtitle={`${numberOfCustomLegalForms} custom legal forms codes uploaded`}
          />
        </li>
        <li>
          <NavItem title="6. Summary" href="/getting-started/summary" />
        </li>
      </ul>
    </nav>
  );
}
