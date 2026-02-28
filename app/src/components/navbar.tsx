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
import { useWorkerStatus, usePipelineStepWeights, COMMAND_LABELS, type ImportStatus, type ImportJobProgress, type PhaseStatus, type PipelineStepWeight } from "@/atoms/worker_status";
import { useMemo, useState } from "react";
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

// Analysis is ~25% of total import time, processing ~75% (measured on real jobs).
const ANALYSIS_WEIGHT = 0.25;
const PROCESSING_WEIGHT = 1 - ANALYSIS_WEIGHT;

/**
 * Compute unified import progress for a single job.
 * Analysis maps to 0-25%, processing maps to 25-100%.
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

/**
 * Extract step weights for a specific phase from the database-loaded weights.
 */
function weightsForPhase(
  allWeights: PipelineStepWeight[],
  phase: string,
): { step: string; weight: number }[] {
  return allWeights
    .filter(w => w.phase === phase)
    .map(({ step, weight }) => ({ step, weight }));
}

/**
 * Compute weighted progress for a phase using the current step from the phase row.
 *
 * The phase row has a single `step` field indicating which command is currently active,
 * plus `total`/`completed` for that step's children. Steps before the current one in the
 * weight table are considered complete (full weight). Steps after get zero weight.
 */
function computeWeightedPhaseProgress(
  phase: PhaseStatus,
  stepWeights: { step: string; weight: number }[],
): number | null {
  if (!phase.active) return null;

  const totalWeight = stepWeights.reduce((acc, sw) => acc + sw.weight, 0);
  if (totalWeight === 0) return null;

  const currentStep = phase.step;
  if (!currentStep) return 0; // Phase exists but no step active yet (pending)

  let earned = 0;
  let foundCurrent = false;

  for (const { step, weight } of stepWeights) {
    if (step === currentStep) {
      // Current step: partial progress based on total/completed
      foundCurrent = true;
      if (phase.total > 0) {
        earned += weight * (phase.completed / phase.total);
      }
      // If total is 0, step just started — contributes 0
      break; // Steps after this haven't started yet
    }
    // Steps before the current one are complete
    earned += weight;
  }

  // If we didn't find the current step in weights (e.g. collect_changes),
  // just return 0 — it's a pre-step
  if (!foundCurrent) return 0;

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
 * Summary of affected unit counts for a phase.
 */
function UnitCountSummary({ phase }: { phase: PhaseStatus }) {
  const parts: string[] = [];
  if (phase.affected_establishment_count)
    parts.push(`~${phase.affected_establishment_count.toLocaleString()} establishments`);
  if (phase.affected_legal_unit_count)
    parts.push(`~${phase.affected_legal_unit_count.toLocaleString()} legal units`);
  if (phase.affected_enterprise_count)
    parts.push(`~${phase.affected_enterprise_count.toLocaleString()} enterprises`);
  if (phase.affected_power_group_count)
    parts.push(`~${phase.affected_power_group_count.toLocaleString()} power groups`);
  if (parts.length === 0) return null;
  return (
    <p className="text-sm text-gray-600 font-medium">
      Processing {parts.join(', ')}
    </p>
  );
}

/**
 * Phase progress popover content.
 */
function PhaseProgressPopover({ phase, stepWeights }: { phase: PhaseStatus; stepWeights: { step: string; weight: number }[] }) {
  const currentStep = phase.step;
  const label = currentStep ? (COMMAND_LABELS[currentStep] ?? currentStep) : 'Pending...';
  const pct = computeWeightedPhaseProgress(phase, stepWeights);

  return (
    <div className="space-y-3">
      <UnitCountSummary phase={phase} />
      {currentStep ? (
        <div>
          <div className="flex justify-between text-sm mb-1">
            <span>{label}</span>
            {phase.total > 1 && <span>{pct}%</span>}
          </div>
          {phase.total > 1 && <Progress value={pct} className="h-2" />}
          {phase.total <= 1 && <p className="text-xs text-gray-500">Running...</p>}
        </div>
      ) : (
        <p className="text-sm text-gray-500">Waiting to start...</p>
      )}
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
  const allWeights = usePipelineStepWeights();
  const phase1Weights = useMemo(() => weightsForPhase(allWeights, 'is_deriving_statistical_units'), [allWeights]);
  const phase2Weights = useMemo(() => weightsForPhase(allWeights, 'is_deriving_reports'), [allWeights]);
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
  const unitsPct = derivingUnits ? computeWeightedPhaseProgress(derivingUnits, phase1Weights) : null;
  const reportsPct = derivingReports ? computeWeightedPhaseProgress(derivingReports, phase2Weights) : null;

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
                      ? (derivingUnits?.active
                        ? <PhaseProgressPopover phase={derivingUnits} stepWeights={phase1Weights} />
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
                      ? (derivingReports?.active
                        ? <PhaseProgressPopover phase={derivingReports} stepWeights={phase2Weights} />
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
