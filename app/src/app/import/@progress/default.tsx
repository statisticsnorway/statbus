"use client";
import { useEffect, useState } from "react";
import { NavItem } from "@/app/getting-started/@progress/nav-item";
import { useBaseData } from "@/atoms/base-data";
import { useImportManager } from "@/atoms/import";
import { useWorkerStatus } from "@/atoms/worker-status";
import { Spinner } from "@/components/ui/spinner";
import { FileText, BarChart2, Building2, Store, Building } from "lucide-react";
import type { WorkerStatus } from "@/atoms/worker-status"; // Import the type

export default function ImportStatus() {
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);

  const {
    counts: {
      legalUnits,
      establishmentsWithLegalUnit,
      establishmentsWithoutLegalUnit,
    },
  } = useImportManager(); // Updated hook call
  const { hasStatisticalUnits } = useBaseData();
  const workerStatus = useWorkerStatus();

  // Safely access workerStatus properties, defaulting if not mounted or workerStatus is null/undefined
  const safeWorkerStatus = workerStatus || {};

  // Determine if any import process is active using workerStatus only
  const isImporting = mounted ? (safeWorkerStatus.isImporting ?? false) : false;
  const isDeriving = mounted ?
    ((safeWorkerStatus.isDerivingUnits || safeWorkerStatus.isDerivingReports) ?? false) : false;

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
              done={mounted ? !!legalUnits : false}
              title="Upload Legal Units"
              href="/import/legal-units"
              subtitle={`${(mounted ? legalUnits : null) || 0} legal units uploaded`}
              icon={<Building2 className="w-4 h-4" />}
              processing={false}
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={mounted ? !!establishmentsWithLegalUnit : false}
              title="Upload Establishments (optional)"
              href="/import/establishments"
              subtitle={`${
                (mounted ? establishmentsWithLegalUnit : null) || 0
              } formal establishments uploaded`}
              icon={<Store className="w-4 h-4" />}
              processing={false}
            />
          </li>
        </ul>
        <h3 className="mb-4">Informal</h3>
        <ul className="text-sm ml-2">
          <li className="mb-6">
            <NavItem
              done={mounted ? !!establishmentsWithoutLegalUnit : false}
              title="Upload Establishments Without Legal Units"
              href="/import/establishments-without-legal-unit"
              subtitle={`${
                (mounted ? establishmentsWithoutLegalUnit : null) || 0
              } informal establishments uploaded`}
              icon={<Building className="w-4 h-4" />}
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
              processing={isImporting}
            />
          </li>
          <li className="mb-6">
            <NavItem
              done={mounted ? hasStatisticalUnits : false}
              title="Analyze Data"
              href="/import/analyse-data-for-search-and-reports"
              subtitle="Prepare for search and reports"
              icon={<BarChart2 className="w-4 h-4" />}
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
