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
import { useWorkerStatus, COMMAND_LABELS, type ImportStatus, type PhaseStatus, type PipelineStep } from "@/atoms/worker_status";
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

/**
 * Compute import progress from active jobs.
 */
function computeImportProgress(jobs: ImportStatus['jobs']): number | null {
  if (jobs.length === 0) return null;
  // Use the average of import_completed_pct and analysis_completed_pct across active jobs
  const total = jobs.reduce((acc, j) => {
    const pct = j.import_completed_pct > 0 ? j.import_completed_pct : j.analysis_completed_pct;
    return acc + (pct ?? 0);
  }, 0);
  return Math.round(total / jobs.length);
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
        const pct = isAnalysing ? job.analysis_completed_pct : job.import_completed_pct;
        const label = isAnalysing ? 'Analysing' : 'Processing';
        const rowInfo = job.total_rows
          ? `${(job.imported_rows ?? 0).toLocaleString()} / ${job.total_rows.toLocaleString()} rows`
          : null;
        return (
          <div key={job.id}>
            <div className="flex justify-between text-sm mb-1">
              <span>Job #{job.id} - {label}</span>
              <span>{pct ?? 0}%</span>
            </div>
            {rowInfo && <p className="text-xs text-gray-500 mb-1">{rowInfo}</p>}
            <Progress value={pct ?? 0} className="h-2" />
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
              <span>{step.completed}/{step.total}</span>
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
  const unitsPct = derivingUnits ? computePhaseProgress(derivingUnits.progress) : null;
  const reportsPct = derivingReports ? computePhaseProgress(derivingReports.progress) : null;

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
                popoverContent={importing && importing.active ? <ImportProgressPopover importing={importing} /> : null}
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
                    popoverContent={derivingUnits && derivingUnits.active ? <PhaseProgressPopover phase={derivingUnits} /> : null}
                  />
                  {/* Reports Link */}
                  <NavLink
                    href="/reports"
                    icon={BarChartHorizontal}
                    label="Reports"
                    isActive={isDerivingReports}
                    isCurrent={pathname.startsWith("/reports")}
                    progressPct={reportsPct}
                    popoverContent={derivingReports && derivingReports.active ? <PhaseProgressPopover phase={derivingReports} /> : null}
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
