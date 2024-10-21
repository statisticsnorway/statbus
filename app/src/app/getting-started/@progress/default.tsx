"use client";
import { useGettingStarted } from "../GettingStartedContext";
import { NavItem } from "@/app/getting-started/@progress/nav-item";

export default function SetupStatus() {
  const {
    activity_category_standard,
    numberOfRegions,
    numberOfLegalUnits,
    numberOfEstablishments,
    numberOfCustomActivityCategoryCodes,
    numberOfCustomSectors,
    numberOfCustomLegalForms,
    numberOfStatisticalUnits,
  } = useGettingStarted();

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
            done={!!numberOfRegions}
            title="2. Upload Regions"
            href="/getting-started/upload-regions"
            subtitle={`${numberOfRegions} regions uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfCustomSectors}
            title="3. Upload Custom Sectors (optional)"
            href="/getting-started/upload-custom-sectors"
            subtitle={`${numberOfCustomSectors} custom sectors uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfCustomLegalForms}
            title="4. Upload Custom Legal Forms (optional)"
            href="/getting-started/upload-custom-legal-forms"
            subtitle={`${numberOfCustomLegalForms} custom legal forms codes uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfCustomActivityCategoryCodes}
            title="5. Upload Custom Activity Category Standard Codes (optional)"
            href="/getting-started/upload-custom-activity-standard-codes"
            subtitle={`${numberOfCustomActivityCategoryCodes} custom activity category codes uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfLegalUnits}
            title="6. Upload Legal Units"
            href="/getting-started/upload-legal-units"
            subtitle={`${numberOfLegalUnits} legal units uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfEstablishments}
            title="7. Upload Establishments"
            href="/getting-started/upload-establishments"
            subtitle={`${numberOfEstablishments} establishments uploaded`}
          />
        </li>
        <li className="mb-6">
          <NavItem
            done={!!numberOfStatisticalUnits}
            title="8. Analysis for Search and Reports"
            href="/getting-started/analyse-data-for-search-and-reports"
            subtitle="Analyse data for search and reports"
          />
        </li>
        <li>
          <NavItem title="9. Summary" href="/getting-started/summary" />
        </li>
      </ul>
    </nav>
  );
}
