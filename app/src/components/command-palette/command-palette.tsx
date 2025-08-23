"use client";

import { useEffect, useState } from "react";
import { ResetConfirmationDialog } from "./reset-confirmation-dialog";
import { useToast } from "@/hooks/use-toast";
import { useAuth } from "@/atoms/auth";
import { useSetAtom } from "jotai";
import { pendingRedirectAtom, stateInspectorVisibleAtom } from "@/atoms/app";
import {
  BarChartHorizontal,
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


export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const { toast } = useToast();
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const { logout } = useAuth();
  const setStateInspectorVisible = useSetAtom(stateInspectorVisibleAtom);

  useEffect(() => {
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
  }, []);

  const handleResetAll = () => {
    setOpen(false);
    const event = new CustomEvent('show-reset-dialog');
    document.dispatchEvent(event);
  };

  const navigate = (path: string) => {
    setOpen(false);
    setPendingRedirect(path);
  };

  const handleToggleStateInspector = () => {
    setStateInspectorVisible((prev) => !prev);
    setOpen(false);
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
          <CommandGroup heading="Main Pages">
            <CommandItem onSelect={() => navigate("/")} value="Start page">
              <Home className="mr-2 h-4 w-4" />
              <span>Start page</span>
            </CommandItem>
            <CommandItem
              onSelect={() => navigate("/import")}
              value="Import"
            >
              <Upload className="mr-2 h-4 w-4" />
              <span>Import</span>
            </CommandItem>
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
            <CommandItem onSelect={() => navigate("/profile")} value="Profile">
              <User className="mr-2 h-4 w-4" />
              <span>Profile</span>
            </CommandItem>
            <CommandItem
              onSelect={async () => {
                setOpen(false);
                await logout();
                // The redirect to "/login" or "/" is now handled by RedirectHandler
                // after logoutAtom sets pendingRedirectAtom (or similar mechanism).
              }}
              value="Logout"
            >
              <LogOut className="mr-2 h-4 w-4" />
              <span>Logout</span>
            </CommandItem>
          </CommandGroup>
          <CommandGroup heading="Other Pages">
            <CommandItem
              onSelect={() => navigate("/getting-started")}
              value="Getting started"
            >
              <Footprints className="mr-2 h-4 w-4" />
              <span>Getting started</span>
            </CommandItem>
            <CommandItem
              onSelect={() => navigate("/getting-started/activity-standard")}
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
              onSelect={() => navigate("/import/jobs")}
              value="Import Jobs"
            >
              <FileSpreadsheet className="mr-2 h-4 w-4" />
              <span>Import Jobs</span>
            </CommandItem>
          </CommandGroup>
          <CommandSeparator />
          <CommandGroup heading="Admin tools">
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
                window.open('/pev2.html', '_blank');
              }}
              value="postgres explain visualizer pev2 query performance"
            >
              <Database className="mr-2 h-4 w-4" />
              <span>Postgres Explain Visualizer</span>
            </CommandItem>
            <CommandItem
              onSelect={handleToggleStateInspector}
              value="toggle state inspector developer tool"
            >
              <Binary className="mr-2 h-4 w-4" />
              <span>Toggle State Inspector</span>
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </CommandDialog>
      <ResetConfirmationDialog />
    </>
  );
}
