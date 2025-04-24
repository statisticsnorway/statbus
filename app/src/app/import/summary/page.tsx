"use client";

import React from "react";
import Link from "next/link";
import { Check, X } from "lucide-react";
import { useBaseData } from "@/app/BaseDataClient";
import { useImportUnits } from "../import-units-context";

export default function ImportCompletedPage() {
  const {
    counts: {
      legalUnits,
      establishmentsWithLegalUnit,
      establishmentsWithoutLegalUnit
    }
  } = useImportUnits();
  const { hasStatisticalUnits } = useBaseData();
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
          success={!!legalUnits}
          successText={`You have uploaded ${legalUnits} legal units.`}
          failureText="You have not uploaded any legal units"
          failureLink={"/import/legal-units"}
        />
        <SummaryBlock
          success={!!establishmentsWithLegalUnit}
          successText={`You have uploaded ${establishmentsWithLegalUnit} establishments with legal units.`}
          failureText="You have not uploaded any establishments with legal units"
          failureLink={"/import/establishments"}
        />
        <SummaryBlock
          success={!!establishmentsWithoutLegalUnit}
          successText={`You have uploaded ${establishmentsWithoutLegalUnit} establishments without legal units.`}
          failureText="You have not uploaded any establishments without legal units"
          failureLink={"/import/establishments-without-legal-unit"}
        />
      </div>

      <SummaryBlock
        success={hasStatisticalUnits}
        successText="Analysis for Search and Reports completed."
        failureText="Statistical Units and Reports are not available"
        failureLink="/getting-started/refresh-statistical-units"
      />
      {hasStatisticalUnits ? (
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
