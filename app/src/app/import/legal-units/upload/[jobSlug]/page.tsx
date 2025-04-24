"use client";

import React, { useEffect } from "react";
import { ImportJobUpload } from "../../../components/import-job-upload";
import { ImportJobDetails } from "../../../components/import-job-details";
import { useImportUnits } from "../../../import-units-context";
import { use } from "react";

export default function LegalUnitsUploadPage({ 
  params 
}: { 
  params: Promise<{ jobSlug: string }> 
}) {
  const { refreshUnitCount, getImportJobBySlug, job } = useImportUnits();
  const { jobSlug } = use(params);
  
  useEffect(() => {
    // Fail fast - load the job on mount if not already loaded
    if (jobSlug && (!job.currentJob || job.currentJob.slug !== jobSlug)) {
      getImportJobBySlug(jobSlug).catch(error => {
        console.error(`Failed to load job ${jobSlug}:`, error);
      });
    }
  }, [jobSlug, getImportJobBySlug, job.currentJob]);

  return (
    <section className="space-y-8">
      <h1 className="text-center text-2xl">Upload Legal Units</h1>
      <p>
        Upload a CSV file containing Legal Units you want to use in your
        analysis.
      </p>

      <ImportJobDetails />
      
      <ImportJobUpload 
        jobSlug={jobSlug}
        nextPage="/import/establishments"
        refreshRelevantCounts={() => refreshUnitCount('legalUnits')}
      />
    </section>
  );
}
