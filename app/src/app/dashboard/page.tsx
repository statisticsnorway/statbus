import { Metadata } from "next";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  AlertTriangle,
  BarChart3,
  Globe2,
  Loader,
  ScrollText,
  Settings,
} from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ReactNode, Suspense } from "react";
import { cn } from "@/lib/utils";
import Link from "next/link";
import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";

export const metadata: Metadata = {
  title: "StatBus | Dashboard",
};

export default async function Dashboard() {
  return (
    <main className="mx-auto flex max-w-5xl flex-col px-2 py-8 md:py-24 w-full">
      <h1 className="mb-12 text-center text-2xl">StatBus Status Dashboard</h1>
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        <Link href="/search?unit_type=enterprise">
          <Suspense fallback={<FallBackCard title="Enterprises" />}>
            <StatisticalUnitCountCard
              unitType="enterprise"
              title="Enterprises"
            />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=legal_unit">
          <Suspense fallback={<FallBackCard title="Legal Units" />}>
            <StatisticalUnitCountCard
              unitType="legal_unit"
              title="Legal Units"
            />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=establishment">
          <Suspense fallback={<FallBackCard title="Establishments" />}>
            <StatisticalUnitCountCard
              unitType="establishment"
              title="Establishments"
            />
          </Suspense>
        </Link>

        <Suspense fallback={<FallBackCard title="Regions" />}>
          <RegionCard />
        </Suspense>

        <Link href="/getting-started/activity-standard">
          <Suspense
            fallback={<FallBackCard title="Activity Category Standard" />}
          >
            <ActivityCategoryCard />
          </Suspense>
        </Link>

        <Suspense fallback={<FallBackCard title="Statistical Variables" />}>
          <StatisticalVariableCountCard />
        </Suspense>

        <Link href="/getting-started/upload-custom-activity-standard-codes">
          <Suspense
            fallback={<FallBackCard title="Custom Activity Category Codes" />}
          >
            <CustomActivityCategoryCard />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&physical_region_path=null">
          <Suspense fallback={<FallBackCard title="Units Missing Region" />}>
            <MissingRegionCard />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&primary_activity_category_path=null">
          <Suspense
            fallback={<FallBackCard title="Units Missing Activity Category" />}
          >
            <MissingActivityCategoryCard />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=enterprise,legal_unit,establishment&invalid_codes=yes">
          <Suspense
            fallback={<FallBackCard title="Units With Import Issues" />}
          >
            <InvalidCodesCard />
          </Suspense>
        </Link>
      </div>
    </main>
  );
}

const StatisticalVariableCountCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("stat_definition")
    .select("", { count: "exact" })
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Statistical Variables"
      icon={<BarChart3 className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};

const ActivityCategoryCard = async () => {
  const client = createClient();

  const { data: settings, error } = await client
    .from("settings")
    .select("activity_category_standard(id,name)")
    .single();

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Activity Category Standard"
      icon={<ScrollText className="h-4" />}
      text={settings?.activity_category_standard?.name ?? "-"}
      failed={!!error}
    />
  );
};

const CustomActivityCategoryCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("activity_category_available_custom")
    .select("", { count: "exact" })
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Custom Activity Category Codes"
      icon={<Settings className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};

const MissingActivityCategoryCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("primary_activity_category_path", null)
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Units Missing Activity Category"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};

const MissingRegionCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .is("physical_region_path", null)
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Units Missing Region"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};

const InvalidCodesCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .not("invalid_codes", "is", null)
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Units With Import Issues"
      icon={<AlertTriangle className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error || (count ?? 0) > 0}
    />
  );
};

const RegionCard = async () => {
  const client = createClient();

  const { count, error } = await client
    .from("region")
    .select("", { count: "exact" })
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title="Regions"
      icon={<Globe2 className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};

const StatisticalUnitCountCard = async ({
  unitType,
  title,
}: {
  readonly unitType: "enterprise" | "legal_unit" | "establishment";
  readonly title: string;
}) => {
  const client = createClient();

  const { count, error } = await client
    .from("statistical_unit")
    .select("", { count: "exact" })
    .eq("unit_type", unitType)
    .limit(0);

  await new Promise((resolve) => setTimeout(resolve, 2000));

  return (
    <DashboardCard
      title={title}
      icon={<StatisticalUnitIcon type={unitType} className="h-4" />}
      text={count?.toString() ?? "-"}
      failed={!!error}
    />
  );
};

const FallBackCard = ({ title }: { readonly title: string }) => {
  return (
    <DashboardCard
      title={title}
      icon={<Loader className="h-4 animate-spin" />}
      text="&nbsp;"
    />
  );
};

const DashboardCard = ({
  title,
  icon,
  text,
  failed,
  className,
}: {
  readonly title: string;
  readonly icon: ReactNode;
  readonly text: string;
  readonly failed?: boolean;
  readonly className?: string;
}) => {
  return (
    <Card className={cn("overflow-hidden", className)}>
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
