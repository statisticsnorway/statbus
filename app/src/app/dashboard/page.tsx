export const dynamic = 'force-dynamic';

import { ReactNode, Suspense } from "react";
import Link from "next/link";
import { StatisticalUnitCountCard } from "@/app/dashboard/statistical-unit-count-card";
import { FallBackCard } from "@/app/dashboard/fallBack-card";
import { RegionCard } from "@/app/dashboard/region-card";
import { InvalidCodesCard } from "@/app/dashboard/invalid-codes-card";
import { MissingRegionCard } from "@/app/dashboard/missing-region-card";
import { MissingActivityCategoryCard } from "@/app/dashboard/missing-activity-category-card";
import { CustomActivityCategoryCard } from "@/app/dashboard/custom-activity-category-card";
import { ActivityCategoryCard } from "@/app/dashboard/activity-category-card";
import { StatisticalVariableCountCard } from "@/app/dashboard/statistical-variable-count-card";
import { Database, Gauge } from "lucide-react";
import { TotalActivityCategoryCard } from "./total-activity-category-card";
import { DashboardSection } from "./dashboard-section";
import { DashboardClientContent } from "./dashboard-client-content";

export default function Dashboard() {
  return (
    <main className="mx-auto flex max-w-5xl flex-col px-2 py-8 md:py-12 w-full space-y-8 lg:space-y-10">
      <h1 className="text-center text-2xl">Statbus Status Dashboard</h1>

      <DashboardClientContent>
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
        <Link href="/regions">
          <Suspense fallback={<FallBackCard title="Region Hierarchy" />}>
            <RegionCard />
          </Suspense>
        </Link>

        <Suspense fallback={<FallBackCard title="Statistical Variables" />}>
          <StatisticalVariableCountCard />
        </Suspense>

        <Link href="/activity-categories?custom=false">
          <Suspense
            fallback={<FallBackCard title="Activity Category Standard" />}
          >
            <ActivityCategoryCard />
          </Suspense>
        </Link>

        <Link href="/activity-categories?custom=true">
          <Suspense
            fallback={<FallBackCard title="Custom Activity Category Codes" />}
          >
            <CustomActivityCategoryCard />
          </Suspense>
        </Link>
        <Link href="/activity-categories">
          <Suspense
            fallback={<FallBackCard title="Total Activity Category Codes" />}
          >
            <TotalActivityCategoryCard />
          </Suspense>
        </Link>
      </DashboardClientContent>

      <DashboardSection
        title="Data quality"
        icon={<Gauge className="w-4 h-4 stroke-current" />}
      >
        <Link href="/search?unit_type=legal_unit,establishment&physical_region_path=null">
          <Suspense fallback={<FallBackCard title="Units Missing Region" />}>
            <MissingRegionCard />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=legal_unit,establishment&primary_activity_category_path=null">
          <Suspense
            fallback={<FallBackCard title="Units Missing Activity Category" />}
          >
            <MissingActivityCategoryCard />
          </Suspense>
        </Link>

        <Link href="/search?unit_type=legal_unit,establishment&invalid_codes=yes">
          <Suspense
            fallback={<FallBackCard title="Units With Import Issues" />}
          >
            <InvalidCodesCard />
          </Suspense>
        </Link>
      </DashboardSection>
    </main>
  );
}

