export const dynamic = 'force-dynamic';

import { ReactNode, Suspense } from "react";
import Link from "next/link";
import { StatisticalUnitCountCard } from "@/app/dashboard/statistical-unit-count-card";
import { FallBackCard } from "@/app/dashboard/fallBack-card";
import { RegionCard } from "@/app/dashboard/region-card";
import { MissingRegionCard, MISSING_REGION_HREF } from "@/app/dashboard/missing-region-card";
import {
  MissingPhysicalLocationCard,
  MISSING_PHYSICAL_LOCATION_HREF,
} from "@/app/dashboard/missing-physical-location-card";
import {
  MissingActivityCategoryCard,
  MISSING_ACTIVITY_CATEGORY_HREF,
} from "@/app/dashboard/missing-activity-category-card";
import { LegalUnitQualityCheckCard } from "@/app/dashboard/legal-unit-quality-check-card";
import { qualityCheckHref } from "@/app/search/filters/url-search-params";
import { CustomActivityCategoryCard } from "@/app/dashboard/custom-activity-category-card";
import { ActivityCategoryCard } from "@/app/dashboard/activity-category-card";
import { StatisticalVariableCountCard } from "@/app/dashboard/statistical-variable-count-card";
import { Database, Gauge } from "lucide-react";
import { TotalActivityCategoryCard } from "./total-activity-category-card";
import { DashboardSection } from "./dashboard-section";
import { DashboardClientContent } from "./dashboard-client-content";
import { CountedUnitsLink } from "./counted-units-link";

export default function Dashboard() {
  return (
    <main className="mx-auto flex max-w-5xl flex-col px-2 py-8 md:py-12 w-full space-y-8 lg:space-y-10">
      <h1 className="text-center text-2xl">Statbus Status Dashboard</h1>

      <DashboardClientContent>
        <CountedUnitsLink unitType="enterprise">
          <Suspense fallback={<FallBackCard title="Enterprises" />}>
            <StatisticalUnitCountCard
              unitType="enterprise"
              title="Enterprises"
            />
          </Suspense>
        </CountedUnitsLink>

        <CountedUnitsLink unitType="legal_unit">
          <Suspense fallback={<FallBackCard title="Legal Units" />}>
            <StatisticalUnitCountCard
              unitType="legal_unit"
              title="Legal Units"
            />
          </Suspense>
        </CountedUnitsLink>

        <CountedUnitsLink unitType="establishment">
          <Suspense fallback={<FallBackCard title="Establishments" />}>
            <StatisticalUnitCountCard
              unitType="establishment"
              title="Establishments"
            />
          </Suspense>
        </CountedUnitsLink>
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
        <Link href={MISSING_REGION_HREF}>
          <Suspense fallback={<FallBackCard title="Units Missing Region" />}>
            <MissingRegionCard />
          </Suspense>
        </Link>

        <Link href={MISSING_ACTIVITY_CATEGORY_HREF}>
          <Suspense
            fallback={<FallBackCard title="Units Missing Activity Category" />}
          >
            <MissingActivityCategoryCard />
          </Suspense>
        </Link>

        <Link href={MISSING_PHYSICAL_LOCATION_HREF}>
          <Suspense
            fallback={<FallBackCard title="Units Missing Physical Location" />}
          >
            <MissingPhysicalLocationCard />
          </Suspense>
        </Link>

        <Link href={qualityCheckHref("establishment_activity_differs")}>
          <Suspense
            fallback={<FallBackCard title="Establishment Activity Differs" />}
          >
            <LegalUnitQualityCheckCard
              check="establishment_activity_differs"
              title="Establishment Activity Differs"
              description="Legal units whose primary establishment has another primary activity"
            />
          </Suspense>
        </Link>

        <Link href={qualityCheckHref("establishments_above_legal_unit")}>
          <Suspense
            fallback={<FallBackCard title="Establishments Above Legal Unit" />}
          >
            <LegalUnitQualityCheckCard
              check="establishments_above_legal_unit"
              title="Establishments Above Legal Unit"
            />
          </Suspense>
        </Link>

        <Link href={qualityCheckHref("legal_unit_above_establishments")}>
          <Suspense
            fallback={<FallBackCard title="Legal Unit Above Establishments" />}
          >
            <LegalUnitQualityCheckCard
              check="legal_unit_above_establishments"
              title="Legal Unit Above Establishments"
            />
          </Suspense>
        </Link>

      </DashboardSection>
    </main>
  );
}

