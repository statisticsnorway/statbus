"use client";

import { useEffect, useState } from "react";
import { useToast } from "@/components/ui/use-toast";
import { useRouter } from "next/navigation";
import {
  BarChartHorizontal,
  Footprints,
  Home,
  ListRestart,
  Pilcrow,
  Search,
  Trash,
  Upload,
  User,
} from "lucide-react";
import {
  refreshStatisticalUnits,
  resetAll,
} from "@/components/command-palette/command-palette-server-actions";

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from "@/components/ui/command";

import DataDump from "@/components/data-dump";

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const { toast } = useToast();
  const router = useRouter();

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

  const handleResetAll = async () => {
    setOpen(false);
    const response = await resetAll();
    toast({
      title: response?.error ? "System Reset Failed" : "System Reset OK",
      description: response?.error ?? "All data has been reset.",
    });

    // @ts-ignore
    if (response.data?.statistical_unit_refresh_now) {
      // @ts-ignore
      console.table(response.data?.statistical_unit_refresh_now, [
        "view_name",
        "refresh_time_ms",
      ]);
    }
  };

  const handleStatisticalUnitsRefresh = async () => {
    setOpen(false);
    const response = await refreshStatisticalUnits();
    toast({
      title: response?.error
        ? "Statistical Units Refresh Failed"
        : "Statistical Units successfully refreshed.",
      description:
        response?.error ?? <DataDump data={response} /> ??
        "Statistical Units have been refreshed.",
    });
  };

  const navigate = (path: string) => {
    setOpen(false);
    router.push(path);
  };

  return (
    <CommandDialog open={open} onOpenChange={setOpen}>
      <CommandInput placeholder="Type a command or search..." />
      <CommandList>
        <CommandEmpty>No results found.</CommandEmpty>
        <CommandGroup heading="Pages">
          <CommandItem onSelect={() => navigate("/")} value="Start page">
            <Home className="mr-2 h-4 w-4" />
            <span>Start page</span>
          </CommandItem>
          <CommandItem
            onSelect={() => navigate("/search")}
            value="Search find statistical units"
          >
            <Search className="mr-2 h-4 w-4" />
            <span>Find statistical units</span>
          </CommandItem>
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
            <span>Upload Regions</span>
          </CommandItem>
          <CommandItem
            value="Upload Custom Activity Category Standards"
            onSelect={() =>
              navigate("/getting-started/upload-custom-activity-standard-codes")
            }
          >
            <Upload className="mr-2 h-4 w-4" />
            <span>Upload Custom Activity Category Standards</span>
          </CommandItem>
          <CommandItem
            onSelect={() => navigate("/getting-started/upload-legal-units")}
            value="Upload Legal Units"
          >
            <Upload className="mr-2 h-4 w-4" />
            <span>Upload Legal Units</span>
          </CommandItem>
          <CommandItem onSelect={() => navigate("/profile")} value="Profile">
            <User className="mr-2 h-4 w-4" />
            <span>Profile</span>
          </CommandItem>
          <CommandItem
            onSelect={() => navigate("/reports")}
            value="Reports drill drilldown"
          >
            <BarChartHorizontal className="mr-2 h-4 w-4" />
            <span>Reports</span>
          </CommandItem>
        </CommandGroup>
        <CommandSeparator />
        <CommandGroup heading="Admin tools">
          <CommandItem
            onSelect={handleResetAll}
            value="admin reset everything clean"
          >
            <Trash className="mr-2 h-4 w-4" />
            <span>Reset Everything</span>
          </CommandItem>
          <CommandItem onSelect={handleStatisticalUnitsRefresh}>
            <ListRestart className="mr-2 h-4 w-4" />
            <span>Refresh Statistical Units</span>
          </CommandItem>
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  );
}
