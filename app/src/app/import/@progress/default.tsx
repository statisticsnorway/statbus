"use client";
import { NavItem } from "@/app/getting-started/@progress/nav-item";
import { useBaseData } from "@/app/BaseDataClient";
import { useImportUnits } from "../import-units-context";

export default function ImportStatus() {
  const {
    numberOfLegalUnits,
    numberOfEstablishmentsWithLegalUnit,
    numberOfEstablishmentsWithoutLegalUnit,
  } = useImportUnits();
  const { hasStatisticalUnits } = useBaseData();

  return (
    <nav>
      <h2 className="text-2xl font-normal mb-12 text-center">
        Import progress
      </h2>
      <ul className="text-sm">
        <h3 className="mb-4">Formal</h3>
        <ul className="text-sm ml-2">
          <li className="mb-6">
            <NavItem
              done={!!numberOfLegalUnits}
              title="Upload Legal Units"
              href="/import/legal-units"
              subtitle={`${numberOfLegalUnits} legal units uploaded`}
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={!!numberOfEstablishmentsWithLegalUnit}
              title="Upload Establishments (optional)"
              href="/import/establishments"
              subtitle={`${numberOfEstablishmentsWithLegalUnit} formal establishments uploaded`}
            />
          </li>
        </ul>
        <h3 className="mb-4">Informal</h3>
        <ul className="text-sm ml-2">
          <li className="mb-6">
            <NavItem
              done={!!numberOfEstablishmentsWithoutLegalUnit}
              title="Upload Establishments Without Legal Units"
              href="/import/establishments-without-legal-unit"
              subtitle={`${numberOfEstablishmentsWithoutLegalUnit} informal establishments uploaded`}
            />
          </li>
        </ul>
        <li className="mb-6">
          <NavItem
            done={hasStatisticalUnits}
            title="Analysis for Search and Reports"
            href="/import/analyse-data-for-search-and-reports"
            subtitle="Analyse data for search and reports"
          />
        </li>
        <li>
          <NavItem title="Summary" href="/import/summary" />
        </li>
      </ul>
    </nav>
  );
}
