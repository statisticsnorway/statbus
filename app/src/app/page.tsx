import { Metadata } from "next";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  AlertTriangle,
  BarChart3,
  Building,
  Globe2,
  ScrollText,
  Settings,
} from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ReactNode } from "react";
import { cn } from "@/lib/utils";
import Link from "next/link";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

export const metadata: Metadata = {
  title: "StatBus | Dashboard",
};

export default async function Dashboard() {
  const client = createClient();

  function countByUnitType(
    unitType: "enterprise" | "legal_unit" | "establishment"
  ) {
    return client
      .from("statistical_unit")
      .select("", { count: "exact" })
      .eq("unit_type", unitType)
      .limit(0);
  }

  const [
    { count: enterpriseCount, error: enterpriseError },
    { count: legalUnitCount, error: legalUnitError },
    { count: establishmentCount, error: establishmentError },
    { count: invalidCodesCount, error: invalidCodesError },
    { count: missingRegionCount, error: missingRegionError },
    { count: missingACCount, error: missingACError },
    { count: regionsCount, error: regionsError },
    { count: statisticalVariablesCount, error: statisticalVariablesError },
    { count: customACCount, error: customACError },
    { data: settings, error: settingsError },
  ] = await Promise.all([
    countByUnitType("enterprise"),
    countByUnitType("legal_unit"),
    countByUnitType("establishment"),
    client
      .from("statistical_unit")
      .select("", { count: "exact" })
      .not("invalid_codes", "is", null)
      .limit(0),
    client
      .from("statistical_unit")
      .select("", { count: "exact" })
      .is("physical_region_path", null)
      .limit(0),
    client
      .from("statistical_unit")
      .select("", { count: "exact" })
      .is("primary_activity_category_path", null)
      .limit(0),
    client.from("region").select("", { count: "exact" }).limit(0),
    client.from("stat_definition").select("", { count: "exact" }).limit(0),
    client
      .from("activity_category_available_custom")
      .select("", { count: "exact" })
      .limit(0),
    client
      .from("settings")
      .select("activity_category_standard(id,name)")
      .single(),
  ]);

  return (
    <main className="mx-auto flex max-w-5xl flex-col px-2 py-8 md:py-24">
      <h1 className="mb-12 text-center text-2xl">StatBus Status Dashboard</h1>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        <Link href="/search?unit_type=enterprise">
          <DashboardCard
            title="Enterprises"
            icon={<StatisticalUnitIcon type="enterprise" className="h-4" />}
            text={enterpriseCount?.toString() ?? "-"}
            failed={!!enterpriseError}
          />
        </Link>

        <Link href="/search?unit_type=legal_unit">
          <DashboardCard
            title="Legal Units"
            icon={<StatisticalUnitIcon type="legal_unit" className="h-4" />}
            text={legalUnitCount?.toString() ?? "-"}
            failed={!!legalUnitError}
          />
        </Link>

        <Link href="/search?unit_type=establishment">
          <DashboardCard
            title="Establishments"
            icon={<StatisticalUnitIcon type="establishment" className="h-4" />}
            text={establishmentCount?.toString() ?? "-"}
            failed={!!establishmentError}
          />
        </Link>

        <DashboardCard
          title="Regions"
          icon={<Globe2 className="h-4" />}
          text={regionsCount?.toString() ?? "-"}
          failed={!!regionsError}
        />

        <Link href="/getting-started/activity-standard">
          <DashboardCard
            title="Activity Category Standard"
            icon={<ScrollText className="h-4" />}
            text={settings?.activity_category_standard?.name ?? "-"}
            failed={!!settingsError}
          />
        </Link>

        <DashboardCard
          title="Statistical Variables"
          icon={<BarChart3 className="h-4" />}
          text={statisticalVariablesCount?.toString() ?? "-"}
          failed={!!statisticalVariablesError}
        />

        <Link href="/getting-started/upload-custom-activity-standard-codes">
          <DashboardCard
            title="Custom Activity Category Codes"
            icon={<Settings className="h-4" />}
            text={customACCount?.toString() ?? "-"}
            failed={!!customACError}
          />
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&physical_region_path=null">
          <DashboardCard
            title="Units Missing Region"
            icon={<AlertTriangle className="h-4" />}
            text={missingRegionCount?.toString() ?? "-"}
            failed={(missingRegionCount ?? 0) > 0 || !!missingRegionError}
          />
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&primary_activity_category_path=null">
          <DashboardCard
            title="Units Missing Activity Category"
            icon={<AlertTriangle className="h-4" />}
            text={missingACCount?.toString() ?? "-"}
            failed={(missingACCount ?? 0) > 0 || !!missingACError}
          />
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&invalid_codes=yes">
          <DashboardCard
            title="Units With Import Issues"
            icon={<AlertTriangle className="h-4" />}
            text={invalidCodesCount?.toString() ?? "-"}
            failed={(invalidCodesCount ?? 0) > 0 || !!invalidCodesError}
          />
        </Link>
      </div>
    </main>
  );
}

const DashboardCard = ({
  title,
  icon,
  text,
  failed,
}: {
  readonly title: string;
  readonly icon: ReactNode;
  readonly text: string;
  readonly failed: boolean;
}) => {
  return (
    <Card className="overflow-hidden">
      <CardHeader
        className={cn(
          "flex flex-row items-center justify-between space-y-0 bg-gray-100 px-3 py-2",
          failed ? "border-orange-400 bg-orange-100" : ""
        )}
      >
        <CardTitle className="text-xs font-medium">{title}</CardTitle>
        {icon}
      </CardHeader>
      <CardContent className="space-y-3 px-3 py-3">
        <div className="text-right text-xl font-semibold">{text}</div>
      </CardContent>
    </Card>
  );
};
