"use client";

"use client";

import React from "react";
import Link from "next/link";
import { Check, X } from "lucide-react";
import { useBaseData, useImportManager } from "@/atoms/hooks";
import { Spinner } from "@/components/ui/spinner"; // Import Spinner

export default function ImportCompletedPage() {
  const {
    counts: {
      legalUnits,
      establishmentsWithLegalUnit,
      establishmentsWithoutLegalUnit,
    },
  } = useImportManager();
  const {
    hasStatisticalUnits,
    loading: baseDataLoading,
    error: baseDataError,
  } = useBaseData();

  return (
    <div className="space-y-8">
      <h1 className="text-center text-2xl">Summary</h1>
      <p className="leading-loose">
        To have a fully functional Statbus, please ensure you have uploaded
        either Legal Units (with or without establishments) or Establishments
        Without Legal Units. If any steps are incomplete, you can click the
        links to complete the steps.
      </p>

      <div className="space-y-6">
        <SummaryBlock
          success={(legalUnits ?? 0) > 0}
          successText={`You have uploaded ${
            legalUnits ?? 0
          } legal units.`}
          failureText="You have not uploaded any legal units"
          failureLink={"/import/legal-units"}
        />
        <SummaryBlock
          success={(establishmentsWithLegalUnit ?? 0) > 0}
          successText={`You have uploaded ${
            establishmentsWithLegalUnit ?? 0
          } establishments with legal units.`}
          failureText="You have not uploaded any establishments with legal units"
          failureLink={"/import/establishments"}
        />
        <SummaryBlock
          success={(establishmentsWithoutLegalUnit ?? 0) > 0}
          successText={`You have uploaded ${
            establishmentsWithoutLegalUnit ?? 0
          } establishments without legal units.`}
          failureText="You have not uploaded any establishments without legal units"
          failureLink={"/import/establishments-without-legal-unit"}
        />
      </div>

      {baseDataLoading ? (
        <div className="flex items-center justify-center space-x-2">
          <Spinner />
          <p>Loading analysis status...</p>
        </div>
      ) : baseDataError ? (
        <div className="text-red-600">
          Error loading analysis status: {baseDataError}
        </div>
      ) : (
        <SummaryBlock
          success={hasStatisticalUnits}
          successText="Analysis for Search and Reports completed."
          failureText="Statistical Units and Reports are not available"
          failureLink="/import/analyse-data-for-search-and-reports"
        />
      )}

      {!baseDataLoading && !baseDataError && hasStatisticalUnits ? (
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
