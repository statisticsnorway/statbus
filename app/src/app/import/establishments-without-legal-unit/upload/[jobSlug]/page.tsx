"use client";

import React from "react";
import { ImportJobUpload } from "../../../components/import-job-upload";
import { ImportJobDetails } from "../../../components/import-job-details";
import { useImportUnits } from "../../../import-units-context";

export default function EstablishmentsWithoutLegalUnitUploadPage({ 
  params 
}: { 
  params: { jobSlug: string } 
}) {
  const { refreshUnitCount } = useImportUnits();
  const { jobSlug } = params;

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Establishments Without Legal Unit</h1>
      <p>
        Upload a CSV file containing establishments without legal units you want to use in your
        analysis.
      </p>

      <ImportJobDetails />
      
      <ImportJobUpload 
        jobSlug={jobSlug}
        nextPage="/import/analyse-data-for-search-and-reports"
        refreshRelevantCounts={() => refreshUnitCount('establishmentsWithoutLegalUnit')}
      />
    </section>
  );
}
