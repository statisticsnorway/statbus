import { Metadata } from "next";
import { Suspense } from "react";
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
