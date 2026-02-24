"use client";
import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from "@/../public/statbus-logo.png";
import Link from "next/link";
import { BarChartHorizontal, Info, Search, Upload } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";
import { CommandPaletteTriggerMobileMenuButton } from "@/components/command-palette/command-palette-trigger-button";
import TimeContextSelector from "@/components/time-context-selector";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useAuth, isAuthenticatedStrictAtom, currentUserAtom } from "@/atoms/auth";
import { useBaseData } from "@/atoms/base-data";
import { useWorkerStatus, COMMAND_LABELS, type ImportStatus, type ImportJobProgress, type PhaseStatus, type PipelineStep } from "@/atoms/worker_status";
import { useState } from "react";
import { usePathname } from "next/navigation";
import { useAtomValue } from "jotai";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Progress } from "@/components/ui/progress";

export function NavbarSkeleton() {
  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Image src={logo} alt="Statbus Logo" className="h-10 w-10" />
      </div>
    </header>
  );
}

/**
 * Compute an overall progress percentage from pipeline steps.
 */
function computePhaseProgress(progress: PipelineStep[]): number | null {
  if (progress.length === 0) return null;
  const totalSum = progress.reduce((acc, s) => acc + s.total, 0);
  const completedSum = progress.reduce((acc, s) => acc + s.completed, 0);
  if (totalSum === 0) return null;
  return Math.round((completedSum / totalSum) * 100);
}

// Analysis is ~25% of total import time, processing ~75% (measured on real jobs).
const ANALYSIS_WEIGHT = 0.25;
const PROCESSING_WEIGHT = 1 - ANALYSIS_WEIGHT;

/**
 * Compute unified import progress for a single job.
 * Analysis maps to 0–25%, processing maps to 25–100%.
 */
function computeJobProgress(job: ImportJobProgress): number {
  const isAnalysing = job.state === 'analysing_data';
  if (isAnalysing) {
    return Math.round((job.analysis_completed_pct ?? 0) * ANALYSIS_WEIGHT);
  }
  return Math.round(ANALYSIS_WEIGHT * 100 + (job.import_completed_pct ?? 0) * PROCESSING_WEIGHT);
}

/**
 * Compute import progress from active jobs (average across all).
 */
function computeImportProgress(jobs: ImportStatus['jobs']): number | null {
  if (jobs.length === 0) return null;
  const total = jobs.reduce((acc, j) => acc + computeJobProgress(j), 0);
  return Math.round(total / jobs.length);
}

// Step weights derived from production wall-clock times (no.statbus.org, 2026-02-24).
// Dataset: 1.1M legal units + 826K establishments, analytics_partition_count=128.
//
// Threading model: Analytics queue has 1 top fiber (sequential) + 4 child fibers (parallel).
// Top-level tasks execute strictly one at a time. PARENT tasks spawn children processed
// by the 4 child fibers; the top fiber blocks until all children complete.
// Serial tasks run synchronously on the top fiber.
//
// Phase 1 — Statistical Units (total ~163 min):
//   derive_statistical_unit:        8,414s wall (2394 children / 4 fibers) → 86%
//   statistical_unit_flush_staging: 1,355s (serial, duration_ms)           → 14%
//
const PHASE1_STEP_WEIGHTS = [
  { step: 'derive_statistical_unit', weight: 86 },
  { step: 'statistical_unit_flush_staging', weight: 14 },
];

// Phase 2 — Reports (total ~28 min per iteration):
//   derive_reports:                    12s (serial, enqueues children)         →  1%
//   derive_statistical_history:        35s wall (384 period children / 4)      →  2%
//   derive_statistical_unit_facet:     27s wall (128 partition children / 4)   →  2%
//   statistical_unit_facet_reduce:     51s (serial, merges partitions)         →  3%
//   derive_statistical_history_facet: 1,401s wall (384 period children / 4)   → 84%
//   statistical_history_facet_reduce:  149s (serial, merges partitions)        →  9%
//
const PHASE2_STEP_WEIGHTS = [
  { step: 'derive_reports', weight: 1 },
  { step: 'derive_statistical_history', weight: 2 },
  { step: 'derive_statistical_unit_facet', weight: 2 },
  { step: 'statistical_unit_facet_reduce', weight: 3 },
  { step: 'derive_statistical_history_facet', weight: 84 },
  { step: 'statistical_history_facet_reduce', weight: 9 },
];

/**
 * Compute weighted progress for a phase using step weights and seenSteps tracking.
 *
 * Steps in pipeline_progress (with total > 0) are in-progress: weight * (completed / total).
 * Steps in seenSteps but not in pipeline_progress have completed: full weight.
 * Steps not yet seen: 0.
 */
function computeWeightedPhaseProgress(
  phase: PhaseStatus,
  stepWeights: { step: string; weight: number }[],
): number | null {
  const totalWeight = stepWeights.reduce((acc, sw) => acc + sw.weight, 0);
  if (totalWeight === 0) return null;

  const progressByStep = new Map(phase.progress.map(s => [s.step, s]));
  const seenSet = new Set(phase.seenSteps);

  let earned = 0;
  for (const { step, weight } of stepWeights) {
    const prog = progressByStep.get(step);
    if (prog && prog.total > 0) {
      // Currently in pipeline_progress — partially done
      earned += weight * (prog.completed / prog.total);
    } else if (seenSet.has(step)) {
      // Was seen but no longer in pipeline_progress — completed
      earned += weight;
    }
    // else: not started yet — contributes 0
  }

  return Math.round((earned / totalWeight) * 100);
}

/**
 * Import progress popover content.
 */
function ImportProgressPopover({ importing }: { importing: ImportStatus }) {
  if (importing.jobs.length === 0) {
    return <p className="text-sm text-gray-500">Import is active...</p>;
  }
  return (
    <div className="space-y-3">
      {importing.jobs.map((job) => {
        const isAnalysing = job.state === 'analysing_data';
        const label = isAnalysing ? 'Analysing' : 'Processing';
        const pct = computeJobProgress(job);
        const rowInfo = !isAnalysing && job.total_rows
          ? `${(job.imported_rows ?? 0).toLocaleString()} / ${job.total_rows.toLocaleString()} rows`
          : null;
        return (
          <div key={job.id}>
            <div className="flex justify-between text-sm mb-1">
              <span>Job #{job.id} - {label}</span>
              <span>{pct}%</span>
            </div>
            {rowInfo && <p className="text-xs text-gray-500 mb-1">{rowInfo}</p>}
            <Progress value={pct} className="h-2" />
          </div>
        );
      })}
    </div>
  );
}

/**
 * Phase progress popover content.
 */
function PhaseProgressPopover({ phase }: { phase: PhaseStatus }) {
  if (phase.progress.length === 0) {
    return <p className="text-sm text-gray-500">Processing...</p>;
  }
  return (
    <div className="space-y-3">
      {phase.progress.map((step) => {
        const label = COMMAND_LABELS[step.step] ?? step.step;
        const pct = step.total > 0 ? Math.round((step.completed / step.total) * 100) : 0;
        return (
          <div key={step.step}>
            <div className="flex justify-between text-sm mb-1">
              <span>{label}</span>
              <span>{pct}%</span>
            </div>
            <Progress value={pct} className="h-2" />
          </div>
        );
      })}
    </div>
  );
}

/**
 * A nav link with optional progress bar and info popover.
 */
function NavLink({
  href,
  icon: Icon,
  label,
  isActive,
  isCurrent,
  progressPct,
  popoverContent,
}: {
  href: string;
  icon: React.ComponentType<{ size: number }>;
  label: string;
  isActive: boolean | null;
  isCurrent: boolean;
  progressPct: number | null;
  popoverContent: React.ReactNode | null;
}) {
  return (
    <div className="relative hidden lg:flex items-center">
      <Link
        href={href}
        className={cn(
          buttonVariants({ variant: "ghost", size: "sm" }),
          "space-x-2 relative overflow-hidden",
          "border-1",
          isActive
            ? "border-yellow-400"
            : isCurrent
              ? "border-white"
              : "border-transparent"
        )}
        style={
          isActive && progressPct !== null
            ? {
                backgroundImage: `linear-gradient(to right, rgba(250, 204, 21, 0.25) ${progressPct}%, transparent ${progressPct}%)`,
              }
            : undefined
        }
      >
        <Icon size={16} />
        <span>{label}</span>
      </Link>
      {popoverContent ? (
        <Popover>
          <PopoverTrigger asChild>
            <button
              className={cn(
                "ml-0.5 p-0.5 rounded",
                isActive
                  ? "text-yellow-400 hover:bg-white/20"
                  : "invisible"
              )}
              aria-label={`${label} progress details`}
            >
              <Info size={14} />
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-80">
            <h4 className="font-medium mb-2 text-sm">{label} Progress</h4>
            {popoverContent}
          </PopoverContent>
        </Popover>
      ) : (
        <span className="ml-0.5 p-0.5 invisible"><Info size={14} /></span>
      )}
    </div>
  );
}

export default function Navbar() {
  const isAuthenticated = useAtomValue(isAuthenticatedStrictAtom);
  const currentUser = useAtomValue(currentUserAtom);
  const { hasStatisticalUnits } = useBaseData();
  const workerStatus = useWorkerStatus();
  const { isImporting, isDerivingUnits, isDerivingReports, importing, derivingUnits, derivingReports } = workerStatus;
  const pathname = usePathname();

  const [isClient, setIsClient] = useState(false);

  useGuardedEffect(() => {
    setIsClient(true);
  }, [], 'Navbar:setIsClient');

  if (!isClient || !isAuthenticated) {
    if (!isAuthenticated && isClient) {
      return (
        <header className="bg-ssb-dark text-white">
          <div className="mx-auto flex max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
            <Link
              href="/"
              className="flex items-center space-x-3 rtl:space-x-reverse"
            >
              <Image src={logo} alt="Statbus Logo" className="h-9 w-9" />
            </Link>
            <div className="flex-1"></div>
            <div className="flex items-center space-x-3">
            </div>
          </div>
        </header>
      );
    }
    if (!isClient) {
       return <NavbarSkeleton />;
    }
  }

  // Compute progress percentages
  const importPct = importing ? computeImportProgress(importing.jobs) : null;
  const unitsPct = derivingUnits ? computeWeightedPhaseProgress(derivingUnits, PHASE1_STEP_WEIGHTS) : null;
  const reportsPct = derivingReports ? computeWeightedPhaseProgress(derivingReports, PHASE2_STEP_WEIGHTS) : null;

  return (
    <header className="bg-ssb-dark text-white">
      <div className="mx-auto grid grid-cols-3 max-w-(--breakpoint-xl) items-center justify-between gap-4 p-2 lg:px-4">
        <Link
          href="/"
          className="flex items-center space-x-3 rtl:space-x-reverse"
        >
          <Image src={logo} alt="Statbus Logo" className="h-9 w-9" />
        </Link>

        {/* Center: Main Navigation Links / Mobile Menu Trigger */}
        <div className="flex flex-1 justify-center space-x-3">
          {isAuthenticated && (
            <>
              {/* Mobile Menu Trigger (Hamburger) */}
              <CommandPaletteTriggerMobileMenuButton className="lg:hidden" />

              {/* Import Link */}
              <NavLink
                href={isImporting ? "/import/jobs" : "/import"}
                icon={Upload}
                label="Import"
                isActive={isImporting}
                isCurrent={pathname.startsWith("/import")}
                progressPct={importPct}
                popoverContent={isImporting
                  ? (importing?.active && importing.jobs.length > 0
                    ? <ImportProgressPopover importing={importing} />
                    : <p className="text-sm text-gray-500">Import is active...</p>)
                  : null}
              />

              {hasStatisticalUnits && (
                <>
                  {/* Search Link */}
                  <NavLink
                    href="/search"
                    icon={Search}
                    label="Statistical Units"
                    isActive={isDerivingUnits}
                    isCurrent={pathname.startsWith("/search")}
                    progressPct={unitsPct}
                    popoverContent={isDerivingUnits
                      ? (derivingUnits?.active && derivingUnits.progress.length > 0
                        ? <PhaseProgressPopover phase={derivingUnits} />
                        : <p className="text-sm text-gray-500">Deriving statistical units...</p>)
                      : null}
                  />
                  {/* Reports Link */}
                  <NavLink
                    href="/reports"
                    icon={BarChartHorizontal}
                    label="Reports"
                    isActive={isDerivingReports}
                    isCurrent={pathname.startsWith("/reports")}
                    progressPct={reportsPct}
                    popoverContent={isDerivingReports
                      ? (derivingReports?.active && derivingReports.progress.length > 0
                        ? <PhaseProgressPopover phase={derivingReports} />
                        : <p className="text-sm text-gray-500">Deriving reports...</p>)
                      : null}
                  />
                </>
              )}
            </>
          )}
        </div>

        {/* Right: Context/Profile/Mobile */}
        <div className="flex items-center justify-end space-x-3">
          {isAuthenticated &&
            hasStatisticalUnits && (
              <TimeContextSelector />
            )}
          {isAuthenticated &&
            currentUser && (
              <>
                <ProfileAvatar className="w-8 h-8 text-ssb-dark hidden lg:flex" />
              </>
            )}
        </div>
      </div>
    </header>
  );
}
