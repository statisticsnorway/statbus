"use client";

import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { ResetConfirmationDialog } from "./reset-confirmation-dialog";
import { useAuth, usePermission } from "@/atoms/auth";
import { useSetAtom, useAtomValue } from "jotai";
import { debugInspectorVisibleAtom } from "@/atoms/app";
import { importDownloadContextAtom } from "@/atoms/import-download-context";
import { loadAllImportDefinitionsAtom, createImportJobFromDefinitionAtom } from "@/atoms/import";
import { useBaseData } from "@/atoms/base-data";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { toast } from "@/hooks/use-toast";
import { getUploadPath } from "@/lib/import-mode-paths";
import type { Tables } from "@/lib/database.types";
import {
  BarChartHorizontal,
  Copy,
  Download,
  Footprints,
  Home,
  LogOut,
  Network,
  Pilcrow,
  Plus,
  Search,
  Trash,
  Upload,
  User,
  Database,
  FileSpreadsheet,
  Binary,
  ChartColumn,
  Users,
  KeyRound,
  ListChecks,
} from "lucide-react";

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from "@/components/ui/command";
import { DialogDescription, DialogTitle } from "@radix-ui/react-dialog";
import { VisuallyHidden } from "@radix-ui/react-visually-hidden";
import { ApiKeyDialog } from "./api-key-dialog";

type ImportJobWithDefinition = Tables<'import_job'> & {
  import_definition: Tables<'import_definition'>;
};

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [pages, setPages] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const page = pages[pages.length - 1];

  // Download flow state
  const [downloadFilter, setDownloadFilter] = useState('');

  // Create-job flow state
  const [allDefinitions, setAllDefinitions] = useState<Tables<'import_definition'>[]>([]);
  const [selectedDefinition, setSelectedDefinition] = useState<Tables<'import_definition'> | null>(null);
  const [selectedTimeContextIdent, setSelectedTimeContextIdent] = useState<string | null>(null);

  // Clone-job flow state
  const [cloneSourceJob, setCloneSourceJob] = useState<ImportJobWithDefinition | null>(null);

  const router = useRouter();
  const { logout } = useAuth();
  const setStateInspectorVisible = useSetAtom(debugInspectorVisibleAtom);
  const { canAccessAdminTools, canAccessGettingStarted, canImport } =
    usePermission();
  const importDownloadContext = useAtomValue(importDownloadContextAtom);
  const doLoadAllDefinitions = useSetAtom(loadAllImportDefinitionsAtom);
  const doCreateJob = useSetAtom(createImportJobFromDefinitionAtom);
  const { timeContexts: allTimeContexts } = useBaseData();

  const availableTimeContexts = allTimeContexts.filter(
    (tc) => (tc.scope === "input" || tc.scope === "input_and_query") && tc.name_when_input,
  );

  useGuardedEffect(
    () => {
    const openPalette = () => {
      setOpen(true);
    };

    const keydown = (e: KeyboardEvent) => {
      if (
        (e.key === "k" || e.key === "K") &&
        (e.metaKey || e.ctrlKey) &&
        e.shiftKey
      ) {
        e.preventDefault();
        openPalette();
      }
    };

    document.addEventListener("keydown", keydown);
    document.addEventListener("toggle-command-palette", openPalette);

    return () => {
      document.removeEventListener("keydown", keydown);
      document.removeEventListener("toggle-command-palette", openPalette);
    };
  }, [], 'CommandPalette:setupListeners');

  const resetPages = () => {
    setPages([]);
    setSearch('');
    setDownloadFilter('');
    setSelectedDefinition(null);
    setSelectedTimeContextIdent(null);
    setCloneSourceJob(null);
    setAllDefinitions([]);
  };

  const handleOpenChange = (v: boolean) => {
    setOpen(v);
    if (!v) resetPages();
  };

  const handleResetAll = () => {
    setOpen(false);
    resetPages();
    const event = new CustomEvent("show-reset-dialog");
    document.dispatchEvent(event);
  };

  const handleShowApiKey = () => {
    setOpen(false);
    resetPages();
    const event = new CustomEvent("show-api-key-dialog");
    document.dispatchEvent(event);
  };

  const navigate = (path: string) => {
    setOpen(false);
    resetPages();
    router.push(path);
  };

  const handleToggleStateInspector = () => {
    setStateInspectorVisible((prev) => !prev);
    setOpen(false);
    resetPages();
  };

  // --- Download flow ---
  const handleDownload = (filter: string, format: string) => {
    if (!importDownloadContext) return;
    setOpen(false);
    resetPages();
    window.open(`/api/import/download?slug=${importDownloadContext.jobSlug}&filter=${filter}&format=${format}`, '_blank');
  };

  // --- Create-job flow ---
  const handleShowCreateJob = async () => {
    setSearch('');
    try {
      const defs = await doLoadAllDefinitions();
      setAllDefinitions(defs);
      setPages((prev) => [...prev, 'create-job-definition']);
    } catch {
      toast({ title: "Failed to load definitions", variant: "destructive" });
    }
  };

  const handleCreateJob = async (review: boolean | null) => {
    if (!selectedDefinition) return;
    setOpen(false);
    resetPages();
    try {
      const job = await doCreateJob({
        definitionId: selectedDefinition.id,
        description: selectedDefinition.name,
        timeContextIdent: selectedTimeContextIdent,
        defaultValidFrom: null,
        defaultValidTo: null,
        review,
      });
      router.push(getUploadPath(selectedDefinition.mode, job.slug));
      toast({ title: `Created job ${job.id}` });
    } catch {
      toast({ title: "Failed to create job", variant: "destructive" });
    }
  };

  // --- Clone-job flow ---
  const handleCloneJob = async () => {
    if (!importDownloadContext) return;
    setSearch('');
    try {
      const client = await getBrowserRestClient();
      const { data, error } = await client
        .from("import_job")
        .select("*, import_definition!inner(*)")
        .eq("slug", importDownloadContext.jobSlug)
        .single();
      if (error) throw error;
      setCloneSourceJob(data as ImportJobWithDefinition);
      setPages((prev) => [...prev, 'clone-job-review']);
    } catch {
      toast({ title: "Failed to load job details", variant: "destructive" });
    }
  };

  const handleClone = async (review: boolean | null) => {
    if (!cloneSourceJob) return;
    setOpen(false);
    resetPages();
    const def = cloneSourceJob.import_definition;
    try {
      const job = await doCreateJob({
        definitionId: cloneSourceJob.definition_id,
        description: cloneSourceJob.description ?? def.name,
        timeContextIdent: cloneSourceJob.time_context_ident,
        defaultValidFrom: cloneSourceJob.default_valid_from,
        defaultValidTo: cloneSourceJob.default_valid_to,
        review,
      });
      router.push(getUploadPath(def.mode, job.slug));
      toast({ title: `Cloned as job ${job.id}` });
    } catch {
      toast({ title: "Failed to clone job", variant: "destructive" });
    }
  };

  const placeholders: Record<string, string> = {
    'download-filter': 'Which rows to download?',
    'download-format': 'Choose format...',
    'create-job-definition': 'Search definitions...',
    'create-job-time': 'Select time context...',
    'create-job-review': 'Select review mode...',
    'clone-job-review': 'Select review mode...',
  };

  return (
    <>
      <CommandDialog open={open} onOpenChange={handleOpenChange}>
        <VisuallyHidden>
          <DialogTitle>Command Palette</DialogTitle>
        </VisuallyHidden>
        <VisuallyHidden>
          <DialogDescription>
            Fast access to all functionality
          </DialogDescription>
        </VisuallyHidden>
        <CommandInput
          value={search}
          onValueChange={setSearch}
          placeholder={placeholders[page ?? ''] ?? "Type a command or search..."}
          onKeyDown={(e) => {
            if (e.key === 'Backspace' && !search && pages.length > 0) {
              e.preventDefault();
              setPages((prev) => prev.slice(0, -1));
            }
          }}
        />
        <CommandList>
          <CommandEmpty>No results found.</CommandEmpty>

          {/* ===== ROOT PAGE ===== */}
          {!page && (
            <>
              {importDownloadContext && canImport && (() => {
                const { totalRows, errorCount, warningCount } = importDownloadContext;
                const okCount = totalRows - errorCount - warningCount;
                return (
                  <>
                    <CommandGroup heading={`Job ${importDownloadContext.jobId}`}>
                      <CommandItem
                        onSelect={() => { setPages([...pages, 'download-filter']); setSearch(''); }}
                        value="download export csv excel spreadsheet rows"
                      >
                        <Download className="mr-2 h-4 w-4" />
                        <span>Download rows...</span>
                        <span className="ml-auto text-xs text-muted-foreground">
                          {totalRows} rows{errorCount > 0 ? `, ${errorCount} errors` : ''}{warningCount > 0 ? `, ${warningCount} warnings` : ''}
                        </span>
                      </CommandItem>
                      <CommandItem
                        onSelect={handleCloneJob}
                        value="clone duplicate copy job re-upload"
                      >
                        <Copy className="mr-2 h-4 w-4" />
                        <span>Clone job for re-upload...</span>
                      </CommandItem>
                    </CommandGroup>
                    <CommandSeparator />
                  </>
                );
              })()}
              {canImport && (
                <>
                  <CommandGroup heading="Import Actions">
                    <CommandItem
                      onSelect={handleShowCreateJob}
                      value="create job import definition custom advanced"
                    >
                      <Plus className="mr-2 h-4 w-4" />
                      <span>Create import job from definition...</span>
                    </CommandItem>
                  </CommandGroup>
                  <CommandSeparator />
                </>
              )}
              <CommandGroup heading="Main Pages">
                <CommandItem onSelect={() => navigate("/")} value="Start page">
                  <Home className="mr-2 h-4 w-4" />
                  <span>Start page</span>
                </CommandItem>
                {canImport && (
                  <CommandItem onSelect={() => navigate("/import")} value="Import">
                    <Upload className="mr-2 h-4 w-4" />
                    <span>Import</span>
                  </CommandItem>
                )}
                <CommandItem
                  onSelect={() => navigate("/search")}
                  value="Find statistical units"
                >
                  <Search className="mr-2 h-4 w-4" />
                  <span>Find statistical units</span>
                </CommandItem>
                <CommandItem
                  onSelect={() => navigate("/reports")}
                  value="Reports"
                >
                  <BarChartHorizontal className="mr-2 h-4 w-4" />
                  <span>Reports</span>
                </CommandItem>
                <CommandItem
                  onSelect={() => navigate("/reports/history-changes")}
                  value="History changes chart"
                >
                  <ChartColumn className="mr-2 h-4 w-4" />
                  <span>History chart</span>
                </CommandItem>
                <CommandItem onSelect={() => navigate("/profile")} value="Profile">
                  <User className="mr-2 h-4 w-4" />
                  <span>Profile</span>
                </CommandItem>
                <CommandItem
                  onSelect={async () => {
                    setOpen(false);
                    resetPages();
                    await logout();
                  }}
                  value="Logout"
                >
                  <LogOut className="mr-2 h-4 w-4" />
                  <span>Logout</span>
                </CommandItem>
                <CommandItem
                  onSelect={handleShowApiKey}
                  value="show copy api key token"
                >
                  <KeyRound className="mr-2 h-4 w-4" />
                  <span>Show API key</span>
                </CommandItem>
              </CommandGroup>
              {(canAccessGettingStarted || canImport) && (
                <CommandGroup heading="Other Pages">
                  {canAccessGettingStarted && (
                    <>
                      <CommandItem
                        onSelect={() => navigate("/getting-started")}
                        value="Getting started"
                      >
                        <Footprints className="mr-2 h-4 w-4" />
                        <span>Getting started</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() =>
                          navigate("/getting-started/activity-standard")
                        }
                        value="Select Activity Category Standard"
                      >
                        <Pilcrow className="mr-2 h-4 w-4" />
                        <span>Select Activity Category Standard</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() => navigate("/getting-started/upload-regions")}
                        value="Upload Regions"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Region Hierarchy</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() =>
                          navigate("/getting-started/upload-custom-sectors")
                        }
                        value="Upload Sectors"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Sectors</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() =>
                          navigate("/getting-started/upload-custom-legal-forms")
                        }
                        value="Upload Legal Forms"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Legal Forms</span>
                      </CommandItem>
                      <CommandItem
                        value="Upload Custom Activity Category Standards"
                        onSelect={() =>
                          navigate(
                            "/getting-started/upload-custom-activity-standard-codes"
                          )
                        }
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Custom Activity Category Standards</span>
                      </CommandItem>
                    </>
                  )}
                  {canImport && (
                    <>
                      <CommandItem
                        onSelect={() => navigate("/import/legal-units")}
                        value="Upload Legal Units"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Legal Units</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() => navigate("/import/establishments")}
                        value="Upload Establishments"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Establishments</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() =>
                          navigate("/import/establishments-without-legal-unit")
                        }
                        value="Upload Establishments Without Legal Unit"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Establishments Without Legal Unit</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() => navigate("/import/legal-relationships")}
                        value="Upload Legal Relationships Power Groups"
                      >
                        <Upload className="mr-2 h-4 w-4" />
                        <span>Upload Legal Relationships</span>
                      </CommandItem>
                      <CommandItem
                        onSelect={() => navigate("/import/jobs")}
                        value="Import Jobs"
                      >
                        <FileSpreadsheet className="mr-2 h-4 w-4" />
                        <span>Import Jobs</span>
                      </CommandItem>
                    </>
                  )}
                </CommandGroup>
              )}
              <CommandSeparator />
              {canAccessAdminTools && (
                <>
                  <CommandGroup heading="Admin tools">
                    <CommandItem
                      onSelect={() => navigate("/admin/users")}
                      value="manage create users"
                    >
                      <Users className="mr-2 h-4 w-4" />
                      <span>Manage users</span>
                    </CommandItem>
                    <CommandItem
                      onSelect={() => navigate("/doc/er")}
                      value="Show ER Diagram"
                    >
                      <Network className="mr-2 h-4 w-4" />
                      <span>Show ER Diagram</span>
                    </CommandItem>
                    <CommandItem
                      onSelect={handleResetAll}
                      value="admin reset everything clean"
                    >
                      <Trash className="mr-2 h-4 w-4" />
                      <span>Reset..</span>
                    </CommandItem>
                    <CommandItem
                      onSelect={() => {
                        setOpen(false);
                        resetPages();
                        window.open("/pev2.html", "_blank");
                      }}
                      value="postgres explain visualizer pev2 query performance"
                    >
                      <Database className="mr-2 h-4 w-4" />
                      <span>Postgres Explain Visualizer</span>
                    </CommandItem>
                    <CommandItem
                      onSelect={() => navigate("/admin/worker-tasks")}
                      value="worker tasks queue inspector background jobs"
                    >
                      <ListChecks className="mr-2 h-4 w-4" />
                      <span>Worker Tasks</span>
                    </CommandItem>
                    <CommandItem
                      onSelect={handleToggleStateInspector}
                      value="toggle debug inspector developer tool"
                    >
                      <Binary className="mr-2 h-4 w-4" />
                      <span>Toggle Debug Inspector</span>
                    </CommandItem>
                  </CommandGroup>
                </>
              )}
            </>
          )}

          {/* ===== DOWNLOAD: PICK FILTER ===== */}
          {page === 'download-filter' && importDownloadContext && (() => {
            const { totalRows, errorCount, warningCount } = importDownloadContext;
            const okCount = totalRows - errorCount - warningCount;
            return (
              <CommandGroup heading="Download which rows?">
                <CommandItem onSelect={() => { setDownloadFilter('full'); setPages([...pages, 'download-format']); setSearch(''); }}
                  value="all full rows">
                  Download all rows ({totalRows})
                </CommandItem>
                {okCount > 0 && (
                  <CommandItem onSelect={() => { setDownloadFilter('ok'); setPages([...pages, 'download-format']); setSearch(''); }}
                    value="ok good rows">
                    <span className="text-green-700">Download OK rows ({okCount})</span>
                  </CommandItem>
                )}
                {warningCount > 0 && (
                  <CommandItem onSelect={() => { setDownloadFilter('warning'); setPages([...pages, 'download-format']); setSearch(''); }}
                    value="warnings invalid codes">
                    <span className="text-amber-600">Download warnings ({warningCount})</span>
                  </CommandItem>
                )}
                {errorCount > 0 && (
                  <CommandItem onSelect={() => { setDownloadFilter('error'); setPages([...pages, 'download-format']); setSearch(''); }}
                    value="errors">
                    <span className="text-red-600">Download errors ({errorCount})</span>
                  </CommandItem>
                )}
              </CommandGroup>
            );
          })()}

          {/* ===== DOWNLOAD: PICK FORMAT ===== */}
          {page === 'download-format' && (
            <CommandGroup heading="Choose format">
              <CommandItem onSelect={() => handleDownload(downloadFilter, 'csv')} value="csv">
                <FileSpreadsheet className="mr-2 h-4 w-4" />
                CSV
              </CommandItem>
              <CommandItem onSelect={() => handleDownload(downloadFilter, 'xlsx')} value="excel xlsx">
                <FileSpreadsheet className="mr-2 h-4 w-4" />
                Excel (XLSX)
              </CommandItem>
            </CommandGroup>
          )}

          {/* ===== CREATE JOB: PICK DEFINITION ===== */}
          {page === 'create-job-definition' && (() => {
            const grouped = Object.groupBy(allDefinitions, (d) => d.mode);
            return Object.entries(grouped).map(([mode, defs]) => (
              <CommandGroup key={mode} heading={mode.replace(/_/g, ' ')}>
                {defs!.map((def) => (
                  <CommandItem key={def.id} onSelect={() => {
                    setSelectedDefinition(def);
                    if (def.valid_time_from === 'job_provided') {
                      setPages([...pages, 'create-job-time']); setSearch('');
                    } else {
                      setPages([...pages, 'create-job-review']); setSearch('');
                    }
                  }} value={`${def.name} ${def.slug} ${def.mode} ${def.custom ? 'custom' : 'system'}`}>
                    <span>{def.name}</span>
                    {def.custom && <span className="ml-2 text-xs text-muted-foreground">(custom)</span>}
                  </CommandItem>
                ))}
              </CommandGroup>
            ));
          })()}

          {/* ===== CREATE JOB: PICK TIME CONTEXT ===== */}
          {page === 'create-job-time' && (
            <CommandGroup heading="Select time context">
              {availableTimeContexts.map((tc) => (
                <CommandItem key={tc.ident} onSelect={() => {
                  setSelectedTimeContextIdent(tc.ident);
                  setPages([...pages, 'create-job-review']); setSearch('');
                }} value={`${tc.name_when_input} ${tc.ident}`}>
                  {tc.name_when_input}
                </CommandItem>
              ))}
            </CommandGroup>
          )}

          {/* ===== CREATE JOB: PICK REVIEW MODE ===== */}
          {page === 'create-job-review' && (
            <CommandGroup heading={`Create: ${selectedDefinition?.name ?? 'job'}`}>
              <CommandItem onSelect={() => handleCreateJob(null)} value="review if errors auto">
                Review if errors (auto)
              </CommandItem>
              <CommandItem onSelect={() => handleCreateJob(true)} value="always review">
                Always review
              </CommandItem>
              <CommandItem onSelect={() => handleCreateJob(false)} value="never review skip">
                Never review
              </CommandItem>
            </CommandGroup>
          )}

          {/* ===== CLONE JOB: PICK REVIEW MODE ===== */}
          {page === 'clone-job-review' && cloneSourceJob && (
            <CommandGroup heading={`Clone: ${cloneSourceJob.description ?? cloneSourceJob.import_definition.name}`}>
              <CommandItem onSelect={() => handleClone(null)} value="review if errors auto">
                Review if errors (auto)
              </CommandItem>
              <CommandItem onSelect={() => handleClone(true)} value="always review">
                Always review
              </CommandItem>
              <CommandItem onSelect={() => handleClone(false)} value="never review skip">
                Never review
              </CommandItem>
            </CommandGroup>
          )}

        </CommandList>
      </CommandDialog>
      <ResetConfirmationDialog />
      <ApiKeyDialog />
    </>
  );
}
