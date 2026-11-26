"use client";

import { useState } from "react";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Switch } from "@/components/ui/switch";
import { qualityCheckExplanation, qualityCheckName } from "@/lib/quality-checks";
import {
  qualityCheckKey,
  useQualityChecks,
  type QualityCheckRow,
} from "@/app/dashboard/quality-checks-data";
import AdminPageLayout from "../page-layout";

/**
 * Admin > Data quality checks: every check of public.quality_check with a switch. Switching a check
 * off writes its row in public.quality_check_switched_off, switching it on deletes it; the dashboard
 * and the search's Quality filter read the same view, so they follow at their next read.
 */
export default function QualityChecksPage() {
  const [version, setVersion] = useState(0);
  const { checks, error } = useQualityChecks(version);
  const [saving, setSaving] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  const setOnDashboard = async (check: QualityCheckRow, on: boolean) => {
    const key = qualityCheckKey(check.rule, check.statDefinitionId);
    setSaving(key);
    setSaveError(null);
    const client = await getBrowserRestClient();
    const result = on
      ? await (check.statDefinitionId === null
          ? client.from("quality_check_switched_off").delete().eq("rule", check.rule).is("stat_definition_id", null)
          : client
              .from("quality_check_switched_off")
              .delete()
              .eq("rule", check.rule)
              .eq("stat_definition_id", check.statDefinitionId))
      : await client
          .from("quality_check_switched_off")
          .insert({ rule: check.rule, stat_definition_id: check.statDefinitionId });
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
      subtitle="Choose which data quality checks the dashboard and the search's Quality filter show. Every check starts on; a switched-off check is still computed, so switching it on shows its number at once."
    >
      {error && <p className="text-sm text-orange-700">The data quality checks could not be read.</p>}
      {saveError && <p className="text-sm text-orange-700">{saveError}</p>}
      {checks && (
        <ul className="divide-y rounded border">
          {checks.map((check) => {
            const key = qualityCheckKey(check.rule, check.statDefinitionId);
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
