"use client"

import {useEffect, useState} from "react";
import {useToast} from "@/components/ui/use-toast";
import {useRouter} from "next/navigation";
import {Footprints, Home, ListRestart, Pilcrow, Trash, Upload, User} from "lucide-react"
import {
  refreshStatisticalUnits,
  resetRegions,
  resetSettings,
  resetUnits
} from "@/components/command-palette/command-palette-actions";

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
} from "@/components/ui/command"

import DataDump from "@/components/data-dump";

export function CommandPalette() {
    const [open, setOpen] = useState(false)
    const {toast} = useToast()
    const router = useRouter()

    useEffect(() => {
        const open = () => {
            setOpen(true)
        }

        const keydown = (e: KeyboardEvent) => {
            if (e.key === "k" && (e.metaKey || e.ctrlKey) && e.shiftKey) {
                e.preventDefault()
                open()
            }
        }

        document.addEventListener("keydown", keydown)
        document.addEventListener("toggle-command-palette", open)

        return () => {
            document.removeEventListener("keydown", keydown)
            document.removeEventListener("toggle-command-palette", open)
        }
    }, [])

    const handleSettingsReset = async () => {
        setOpen(false)
        const response = await resetSettings()
        toast({
            title: response?.error ? "Settings Reset Failed" : "Settings Reset OK",
            description: response?.error ?? "All settings have been reset to their default values.",
        })
    }

    const handleRegionsReset = async () => {
        setOpen(false)
        const response = await resetRegions()
        toast({
            title: response?.error ? "Regions Reset Failed" : "Regions Reset OK",
            description: response?.error ?? "All regions have been reset.",
        })
    }

    const handleUnitsReset = async () => {
        setOpen(false)
        const response = await resetUnits()
        toast({
            title: response?.error ? "Units Reset Failed" : "Units Reset OK",
            description: response?.error ?? "All units have been reset.",
        })

        /*
         * Refresh materialized view after resetting all units
         */

        setTimeout(async () => {
            await handleStatisticalUnitsRefresh()
        }, 2500)
    }

    const handleStatisticalUnitsRefresh = async () => {
        setOpen(false)
        const response = await refreshStatisticalUnits()
        toast({
            title: response?.error ? "Statistical Units Refresh Failed" : "Statistical Units successfully refreshed.",
            description: response?.error ?? <DataDump data={response} /> ?? "Statistical Units have been refreshed.",
        })
    }

    const navigate = (path: string) => {
        setOpen(false)
        router.push(path)
    }

    return (
        <CommandDialog open={open} onOpenChange={setOpen}>
            <CommandInput placeholder="Type a command or search..."/>
            <CommandList>
                <CommandEmpty>No results found.</CommandEmpty>
                <CommandGroup heading="Admin tools">
                    <CommandItem onSelect={handleSettingsReset}>
                        <Trash className="mr-2 h-4 w-4"/>
                        <span>Reset Settings</span>
                    </CommandItem>
                    <CommandItem onSelect={handleRegionsReset}>
                        <Trash className="mr-2 h-4 w-4"/>
                        <span>Reset Regions</span>
                    </CommandItem>
                    <CommandItem onSelect={handleUnitsReset}>
                        <Trash className="mr-2 h-4 w-4"/>
                        <span>Reset All units</span>
                    </CommandItem>
                    <CommandItem onSelect={handleStatisticalUnitsRefresh}>
                        <ListRestart className="mr-2 h-4 w-4"/>
                        <span>Refresh Statistical Units</span>
                    </CommandItem>
                </CommandGroup>
                <CommandSeparator/>
                <CommandGroup heading="Pages">
                    <CommandItem onSelect={() => navigate("/getting-started")}>
                        <Footprints className="mr-2 h-4 w-4"/>
                        <span>Getting started</span>
                    </CommandItem>
                    <CommandItem onSelect={() => navigate("/getting-started/activity-standard")}>
                        <Pilcrow className="mr-2 h-4 w-4"/>
                        <span>Select Activity Category Standard</span>
                    </CommandItem>
                    <CommandItem onSelect={() => navigate("/getting-started/upload-regions")}>
                        <Upload className="mr-2 h-4 w-4"/>
                        <span>Upload Regions</span>
                    </CommandItem>
                    <CommandItem onSelect={() => navigate("/getting-started/upload-custom-activity-standard-codes")}>
                        <Upload className="mr-2 h-4 w-4"/>
                        <span>Upload Custom Activity Category Standards</span>
                    </CommandItem>
                    <CommandItem onSelect={() => navigate("/getting-started/upload-legal-units")}>
                        <Upload className="mr-2 h-4 w-4"/>
                        <span>Upload Legal Units</span>
                    </CommandItem>
                    <CommandItem onSelect={() => navigate("/profile")}>
                        <User className="mr-2 h-4 w-4"/>
                        <span>Profile</span>
                    </CommandItem>
                    <CommandItem onSelect={() => navigate("/")}>
                        <Home className="mr-2 h-4 w-4"/>
                        <span>Start page</span>
                    </CommandItem>
                </CommandGroup>
            </CommandList>
        </CommandDialog>
    )
}
