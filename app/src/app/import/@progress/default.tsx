"use client";
import { NavItem } from "@/app/getting-started/@progress/nav-item";
import { useBaseData } from "@/app/BaseDataClient";
import { useImportUnits } from "../import-units-context";
import { Spinner } from "@/components/ui/spinner";
import { FileText, BarChart2, Building2, Store, Building } from "lucide-react";

export default function ImportStatus() {
  const {
    counts: {
      legalUnits,
      establishmentsWithLegalUnit,
      establishmentsWithoutLegalUnit
    },
    job: { currentJob }
  } = useImportUnits();
  const { hasStatisticalUnits, workerStatus } = useBaseData();
  
  // Determine if any import process is active
  const isImporting = workerStatus.isImporting || 
                     (currentJob && 
                      ["processing", "analyzing", "uploading"].includes(currentJob.state));

  return (
    <nav>
      <h2 className="text-2xl font-normal mb-12 text-center">
        Import
      </h2>
      
      {isImporting && (
        <div className="bg-yellow-50 border border-yellow-200 p-3 rounded-md mb-6 flex items-center">
          <Spinner className="h-4 w-4 mr-2" />
          <span className="text-sm text-yellow-800">
            Import in progress...
          </span>
        </div>
      )}
      
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
              // Use correct states: analysing_data or importing_data likely indicate processing
              processing={(["analysing_data", "importing_data"].includes(currentJob?.state ?? "") &&
                         currentJob?.slug.includes("legal_unit")) ?? false}
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={!!establishmentsWithLegalUnit}
              title="Upload Establishments (optional)"
              href="/import/establishments"
              subtitle={`${establishmentsWithLegalUnit || 0} formal establishments uploaded`}
              icon={<Store className="w-4 h-4" />}
              // Use correct states
              processing={(["analysing_data", "importing_data"].includes(currentJob?.state ?? "") &&
                         currentJob?.slug.includes("establishment_for_lu")) ?? false}
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
              subtitle={`${establishmentsWithoutLegalUnit || 0} informal establishments uploaded`}
              icon={<Building className="w-4 h-4" />}
              // Use correct states
              processing={(["analysing_data", "importing_data"].includes(currentJob?.state ?? "") &&
                         currentJob?.slug.includes("establishment_without_lu")) ?? false}
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
              processing={false}
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={hasStatisticalUnits}
              title="Analyze Data"
              href="/import/analyse-data-for-search-and-reports"
              subtitle="Prepare for search and reports"
              icon={<BarChart2 className="w-4 h-4" />}
              processing={(workerStatus.isDerivingUnits || workerStatus.isDerivingReports) ?? false}
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
