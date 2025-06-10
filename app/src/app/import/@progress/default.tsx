"use client";
import { NavItem } from "@/app/getting-started/@progress/nav-item";
import { useBaseData } from "@/atoms/hooks";
import { useImportManager } from "@/atoms/hooks"; // Updated import
import { Spinner } from "@/components/ui/spinner";
import { FileText, BarChart2, Building2, Store, Building } from "lucide-react";

export default function ImportStatus() {
  const {
    counts: {
      legalUnits,
      establishmentsWithLegalUnit,
      establishmentsWithoutLegalUnit,
    },
    // No longer need importState here
  } = useImportManager(); // Updated hook call
  const { hasStatisticalUnits, workerStatus } = useBaseData();

  // Determine if any import process is active using workerStatus only
  const isImporting = workerStatus.isImporting ?? false;
  const isDeriving =
    (workerStatus.isDerivingUnits || workerStatus.isDerivingReports) ?? false;

  return (
    <nav>
      <h2 className="text-2xl font-normal mb-12 text-center">
        Import
      </h2>
      <ul className="text-sm">
        <h3 className="mb-4">Formal</h3>
        <ul className="text-sm ml-2">
          <li className="mb-6">
            <NavItem
              done={!!legalUnits}
              title="Upload Legal Units"
              href="/import/legal-units"
              subtitle={`${legalUnits || 0} legal units uploaded`}
              icon={<Building2 className="w-4 h-4" />}
              // Simplified processing indicator - maybe just use general isImporting?
              // Or remove processing indicator from individual steps?
              // Let's remove it for now for simplicity, as we can't easily tell *which* type is importing.
              // processing={isImporting} // Option 1: General flag
              processing={false} // Option 2: Remove specific indicator
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={!!establishmentsWithLegalUnit}
              title="Upload Establishments (optional)"
              href="/import/establishments"
              subtitle={`${
                establishmentsWithLegalUnit || 0
              } formal establishments uploaded`}
              icon={<Store className="w-4 h-4" />}
              // Remove specific indicator
              processing={false}
            />
          </li>
        </ul>
        <h3 className="mb-4">Informal</h3>
        <ul className="text-sm ml-2">
          <li className="mb-6">
            <NavItem
              done={!!establishmentsWithoutLegalUnit}
              title="Upload Establishments Without Legal Units"
              href="/import/establishments-without-legal-unit"
              subtitle={`${
                establishmentsWithoutLegalUnit || 0
              } informal establishments uploaded`}
              icon={<Building className="w-4 h-4" />}
              // Remove specific indicator
              processing={false}
            />
          </li>
        </ul>
        <h3 className="mb-4">Progress</h3>
        <ul className="text-sm ml-2">
          <li className="mb-6">
            <NavItem
              done={false}
              title="View Import Jobs"
              href="/import/jobs"
              subtitle="Monitor ongoing imports"
              icon={<FileText className="w-4 h-4" />}
              // Use the general isImporting flag here
              processing={isImporting}
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={hasStatisticalUnits}
              title="Analyze Data"
              href="/import/analyse-data-for-search-and-reports"
              subtitle="Prepare for search and reports"
              icon={<BarChart2 className="w-4 h-4" />}
              // Use the combined isDeriving flag
              processing={isDeriving}
            />
          </li>
        </ul>
        <li>
          <NavItem 
            title="Summary" 
            href="/import/summary" 
          />
        </li>
      </ul>
    </nav>
  );
}
