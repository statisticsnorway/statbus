"use client";

import { useState } from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Switch } from "@/components/ui/switch";
import { qualityCheckExplanation, qualityCheckName } from "@/lib/quality-checks";
import { useQualityChecks, type QualityCheckRow } from "@/app/dashboard/quality-checks-data";
import AdminPageLayout from "../page-layout";

/**
 * Admin > Data quality checks: every check in use of public.quality_check with a switch, which
 * writes the check's switched_on; the dashboard and the search's Quality filter read the same
 * table, so they follow at their next read.
 */
export default function QualityChecksPage() {
  const [version, setVersion] = useState(0);
  const { checks, error } = useQualityChecks(version);
  const [saving, setSaving] = useState<number | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  const setOnDashboard = async (check: QualityCheckRow, on: boolean) => {
    setSaving(check.id);
    setSaveError(null);
    const client = await getBrowserRestClient();
    const result = await client.from("quality_check").update({ switched_on: on }).eq("id", check.id);
    setSaving(null);
    if (result.error) {
      setSaveError(`${qualityCheckName(check.rule, check.statName)}: ${result.error.message}`);
      return;
    }
    setVersion((v) => v + 1);
  };

  return (
    <AdminPageLayout
      title="Data quality checks"
      subtitle="Choose which data quality checks the dashboard and the search's Quality filter show. A new installation shows a starting set: units missing region, units missing activity category and secondary activity equals primary. Every other check starts off; a switched-off check is still computed, so switching it on shows its number at once."
    >
      {error && <p className="text-sm text-orange-700">The data quality checks could not be read.</p>}
      {saveError && <p className="text-sm text-orange-700">{saveError}</p>}
      {checks && (
        <ul className="divide-y rounded border">
          {checks.map((check) => {
            const key = check.id;
            const name = qualityCheckName(check.rule, check.statName);
            return (
              <li key={key} className="flex items-start justify-between gap-4 p-3">
                <div>
                  <p className="font-medium">{name}</p>
                  <p className="text-sm text-gray-600">{qualityCheckExplanation(check.rule, check.statName)}</p>
                </div>
                <Switch
                  checked={check.onDashboard}
                  disabled={saving !== null}
                  onCheckedChange={(on) => setOnDashboard(check, on)}
                  aria-label={`Show ${name}`}
                />
              </li>
            );
          })}
        </ul>
      )}
    </AdminPageLayout>
  );
}
