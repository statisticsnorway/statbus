"use client";

import { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { StatisticalUnitDetailsLinkWithSubPath } from "@/components/statistical-unit-details-link-with-sub-path";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Asterisk, Info } from "lucide-react";
import { thousandSeparator } from "@/lib/number-utils";
import { useBaseData } from "@/atoms/base-data";
import { Tables } from "@/lib/database.types";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "../ui/tooltip";
import { Badge } from "../ui/badge";
import { usePermission } from "@/atoms/auth";
import { SetPrimaryUnit } from "./set-primary-unit";
import { establishmentValues, legalUnitTotalFormula } from "./total-formula";
import { TotalRuleInfo, type TotalUnitType } from "./total-rule-info";
import type { Enums } from "@/lib/database.types";

interface TopologyItemProps {
  readonly active?: boolean;
  readonly children?: ReactNode;
  readonly type:
    | "legal_unit"
    | "establishment"
    | "enterprise"
    | "power_group";
  readonly id: number;
  readonly primary?: boolean;
  readonly parentName?: string | null;
  readonly currentPrimaryName?: string | null;
  readonly unit: LegalUnit | Establishment;
  readonly stats?: StatisticalUnitStats;
}

export function TopologyItem({
  id,
  type,
  unit,
  active,
  primary,
  parentName,
  currentPrimaryName,
  children,
  stats,
}: TopologyItemProps) {
  const { canEdit } = usePermission();
  const { statDefinitions } = useBaseData();
  const primaryActivity = unit.activity?.find(
    (act) => act.type === "primary"
  )?.activity_category;
  const location = unit.location?.find((loc) => loc.type === "physical");
  const isInformal =
    (type === "establishment" && !(unit as Establishment).legal_unit_id) ||
    (type === "enterprise" && "legal_unit_id" in unit);
  const canSetPrimary =
    canEdit &&
    active &&
    !!parentName &&
    (type === "establishment" || type === "legal_unit");
  return (
    <>
      <StatisticalUnitDetailsLinkWithSubPath
        id={id}
        type={type}
        className={cn("mb-2 block")}
      >
        <Card className="overflow-hidden">
          <CardHeader
            className={cn(
              "flex flex-row items-center justify-between space-y-0 bg-gray-100 px-3 py-1",
              active && "bg-gray-300"
            )}
          >
            <div className="flex">
              <CardTitle className="text-xs font-medium">{unit.name}</CardTitle>
              {unit.status?.used_for_counting === false && (
                <div className="self-center pl-1">
                  <TooltipProvider>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Info className="h-4 w-4 fill-blue-300 stroke-gray-700" />
                      </TooltipTrigger>
                      <TooltipContent>
                        <span className="text-sm">
                          This unit has status{" "}
                          <strong>{unit.status?.name}</strong> and is therefore
                          not included in aggregates.
                        </span>
                      </TooltipContent>
                    </Tooltip>
                  </TooltipProvider>
                </div>
              )}
            </div>
            <div className="flex items-center space-x-1">
              {primary ? (
                <Badge
                  variant="outline"
                  className="rounded-full border-amber-300 bg-amber-50 text-xs text-amber-800"
                  title="This is a primary unit"
                >
                  Primary
                </Badge>
              ) : (
                canSetPrimary && (
                  <SetPrimaryUnit
                    type={type}
                    id={id}
                    name={unit.name}
                    parentName={parentName}
                    currentPrimaryName={currentPrimaryName}
                  />
                )
              )}

              <StatisticalUnitIcon
                type={type}
                className="w-4"
                hasLegalUnit={!isInformal}
              />
            </div>
          </CardHeader>
          <CardContent className="topology-item-content space-y-3 px-3 pb-2 pt-2">
            <div className="flex justify-between space-x-3 text-center">
              <TopologyItemInfo
                className="flex-1"
                title="Region"
                value={location?.region?.name}
              />
              <TopologyItemInfo
                className="flex-1"
                title="Country"
                value={location?.country?.name}
              />
              {statDefinitions.map(
                (statDefinition: Tables<"stat_definition_enabled">) => {
                  const metric = stats?.stats_summary?.[statDefinition.code];
                  const statsSum = metric && "sum" in metric ? metric.sum : undefined;
                  const stat = unit.stat_for_unit?.find(
                    (s) => s.stat_definition_id === statDefinition.id
                  );
                  const value =
                    stat?.value_int ??
                    stat?.value_bool ??
                    stat?.value_float ??
                    stat?.value_string;
                  const formattedValue =
                    typeof value === "number"
                      ? thousandSeparator(value)
                      : value;
                  const formula =
                    type === "legal_unit" && typeof value === "number" && typeof statsSum === "number" && statDefinition.id !== null
                      ? legalUnitTotalFormula(value, statsSum, establishmentValues(unit as LegalUnit, statDefinition.id))
                      : undefined;
                  return (
                    <TopologyItemInfo
                      key={statDefinition.id}
                      className="flex-1"
                      title={statDefinition.name!}
                      value={type !== "enterprise" && formattedValue}
                      sum={thousandSeparator(statsSum)}
                      formula={formula}
                      variableName={statDefinition.name ?? statDefinition.code ?? ""}
                      totalUnitType={type === "establishment" ? undefined : type}
                      rule={statDefinition.lu_es_rollup}
                      status={unit.status}
                    />
                  );
                }
              )}
            </div>
            <TopologyItemInfo
              title="Primary Activity"
              value={
                primaryActivity
                  ? `${primaryActivity?.code} - ${primaryActivity?.name}`
                  : undefined
              }
            />
          </CardContent>
        </Card>
      </StatisticalUnitDetailsLinkWithSubPath>
      <ul className="pl-4">{children}</ul>
    </>
  );
}

interface TopologyItemInfoProps {
  title: string;
  value?: string | number | boolean | null;
  fallbackValue?: string;
  className?: string;
  sum?: string | number | boolean | null;
  /**
   * How the total after Σ was made, written after "=": "364 + 5" for a variable that adds the
   * legal unit's own value to its establishments' sum, "max(364, 5)" for one that takes the larger
   * (stat_definition.lu_es_rollup, s465ff), with the rule it applies. Absent when the total is a
   * single level's value.
   */
  formula?: { readonly text: string; readonly rule: "sum" | "max" };
  /** The variable's name, for the ⓘ after Σ. */
  variableName?: string;
  /** Whose total Σ is, which decides how it is made; an establishment has no total of its own. */
  totalUnitType?: TotalUnitType;
  /** The variable's legal unit rule (stat_definition.lu_es_rollup), for a legal unit's Σ. */
  rule?: Enums<"lu_es_rollup"> | null;
  status?: Status;
}

const TopologyItemInfo = ({
  title,
  value,
  fallbackValue = "-",
  className,
  sum,
  formula,
  variableName,
  totalUnitType,
  rule,
  status,
}: TopologyItemInfoProps) => (
  <div className={cn("flex flex-col space-y-0 text-left", className)}>
    <span className="text-xs font-medium uppercase text-gray-500">{title}</span>
    <span
      className={`text-sm ${status?.used_for_counting === false && "italic text-stone-500"}`}
      title={`This unit has status ${status?.name}, therefore this value is not included in aggregates.`}
    >
      {value ?? fallbackValue}
    </span>
    {sum && (
      <div className="inline-flex items-baseline gap-1 whitespace-nowrap" data-total-formula={formula?.text ?? ""}>
        {/* Greek capital sigma (U+03A3), a letter on the text's baseline; the n-ary summation sign
            U+2211 is a large operator that sits below the line beside the number. */}
        <span className="text-sm font-semibold">&#931;</span>
        <span className="text-sm font-semibold">{sum}</span>
        {formula && <span className="text-xs text-gray-500">= {formula.text}</span>}
        {totalUnitType && (
          <TotalRuleInfo unitType={totalUnitType} variableName={variableName ?? title} rule={formula?.rule ?? rule ?? null} />
        )}
      </div>
    )}
  </div>
);
