"use client";

import { useState } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { useRouter } from "next/navigation";
import { ResetConfirmationDialog } from "./reset-confirmation-dialog";
import { useAuth, usePermission } from "@/atoms/auth";
import { useSetAtom, useAtomValue } from "jotai";
import { debugInspectorVisibleAtom } from "@/atoms/app";
import { importDownloadContextAtom } from "@/atoms/import-download-context";
import {
  BarChartHorizontal,
  Download,
  Footprints,
  Home,
  ListRestart,
  LogOut,
  Network,
  Pilcrow,
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


export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const { logout } = useAuth();
  const setStateInspectorVisible = useSetAtom(debugInspectorVisibleAtom);
  const { canAccessAdminTools, canAccessGettingStarted, canImport } =
    usePermission();
  const importDownloadContext = useAtomValue(importDownloadContextAtom);
  useGuardedEffect(
    () => {
    const open = () => {
      setOpen(true);
    };

    const keydown = (e: KeyboardEvent) => {
      if (
        (e.key === "k" || e.key === "K") &&
        (e.metaKey || e.ctrlKey) &&
        e.shiftKey
      ) {
        e.preventDefault();
        open();
      }
    };

    document.addEventListener("keydown", keydown);
    document.addEventListener("toggle-command-palette", open);

    return () => {
      document.removeEventListener("keydown", keydown);
      document.removeEventListener("toggle-command-palette", open);
    };
  }, [], 'CommandPalette:setupListeners');

  const handleResetAll = () => {
    setOpen(false);
    const event = new CustomEvent("show-reset-dialog");
    document.dispatchEvent(event);
  };

  const handleShowApiKey = () => {
    setOpen(false);
    const event = new CustomEvent("show-api-key-dialog");
    document.dispatchEvent(event);
  };

  const navigate = (path: string) => {
    setOpen(false);
    router.push(path);
  };

  const handleToggleStateInspector = () => {
    setStateInspectorVisible((prev) => !prev);
    setOpen(false);
  };

  const handleDownload = (filter: string, format: string) => {
    if (!importDownloadContext) return;
    setOpen(false);
    window.open(`/api/import/download?slug=${importDownloadContext.jobSlug}&filter=${filter}&format=${format}`, '_blank');
  };

  return (
    <>
      <CommandDialog open={open} onOpenChange={setOpen}>
        <VisuallyHidden>
          <DialogTitle>Command Palette</DialogTitle>
        </VisuallyHidden>
        <VisuallyHidden>
          <DialogDescription>
            Fast access to all functionality
          </DialogDescription>
        </VisuallyHidden>
        <CommandInput placeholder="Type a command or search..." />
        <CommandList>
          <CommandEmpty>No results found.</CommandEmpty>
          {importDownloadContext && canImport && (() => {
            const { totalRows, errorCount, warningCount } = importDownloadContext;
            const okCount = totalRows - errorCount - warningCount;
            return (
              <>
                <CommandGroup heading={`Downloads for Job ${importDownloadContext.jobId}`}>
                  <CommandItem onSelect={() => handleDownload('full', 'csv')} value="download all full rows csv spreadsheet">
                    <Download className="mr-2 h-4 w-4" />
                    <span>Download all rows (CSV)</span>
                  </CommandItem>
                  <CommandItem onSelect={() => handleDownload('full', 'xlsx')} value="download all full rows excel spreadsheet xlsx">
                    <Download className="mr-2 h-4 w-4" />
                    <span>Download all rows (Excel)</span>
                  </CommandItem>
                  {okCount > 0 && (
                    <>
                      <CommandItem onSelect={() => handleDownload('ok', 'csv')} value="download ok good rows csv">
                        <Download className="mr-2 h-4 w-4 text-green-600" />
                        <span className="text-green-700">Download OK rows (CSV)</span>
                      </CommandItem>
                      <CommandItem onSelect={() => handleDownload('ok', 'xlsx')} value="download ok good rows excel xlsx">
                        <Download className="mr-2 h-4 w-4 text-green-600" />
                        <span className="text-green-700">Download OK rows (Excel)</span>
                      </CommandItem>
                    </>
                  )}
                  {warningCount > 0 && (
                    <>
                      <CommandItem onSelect={() => handleDownload('warning', 'csv')} value="download warnings invalid codes csv">
                        <Download className="mr-2 h-4 w-4 text-amber-500" />
                        <span className="text-amber-600">Download warnings (CSV)</span>
                      </CommandItem>
                      <CommandItem onSelect={() => handleDownload('warning', 'xlsx')} value="download warnings invalid codes excel xlsx">
                        <Download className="mr-2 h-4 w-4 text-amber-500" />
                        <span className="text-amber-600">Download warnings (Excel)</span>
                      </CommandItem>
                    </>
                  )}
                  {errorCount > 0 && (
                    <>
                      <CommandItem onSelect={() => handleDownload('error', 'csv')} value="download errors csv">
                        <Download className="mr-2 h-4 w-4 text-red-600" />
                        <span className="text-red-600">Download errors (CSV)</span>
                      </CommandItem>
                      <CommandItem onSelect={() => handleDownload('error', 'xlsx')} value="download errors excel xlsx">
                        <Download className="mr-2 h-4 w-4 text-red-600" />
                        <span className="text-red-600">Download errors (Excel)</span>
                      </CommandItem>
                    </>
                  )}
                </CommandGroup>
                <CommandSeparator />
              </>
            );
          })()}
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
                await logout();
                // The redirect to "/login" is handled by the navigation state machine
                // in response to the auth state changing.
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
        </CommandList>
      </CommandDialog>
      <ResetConfirmationDialog />
      <ApiKeyDialog />
    </>
  );
}
