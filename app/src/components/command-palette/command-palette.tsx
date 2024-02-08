"use client"

import {useEffect, useState} from "react";
import {useToast} from "@/components/ui/use-toast";
import {useRouter} from "next/navigation";
import {Footprints, Home, ListRestart, Pilcrow, Trash, Upload, User} from "lucide-react"
import {
    refreshStatisticalUnits,
    resetLegalUnits,
    resetRegions,
    resetSettings
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

    const handleLegalUnitsReset = async () => {
        setOpen(false)
        const response = await resetLegalUnits()
        toast({
            title: response?.error ? "Legal Units Reset Failed" : "Legal Units Reset OK",
            description: response?.error ?? "All Legal Units have been reset.",
        })
    }

    const handleStatisticalUnitsRefresh = async () => {
        setOpen(false)
        const response = await refreshStatisticalUnits()
        toast({
          title: response?.error ? "Statistical Units Refresh Failed" : "Statistical Units successfully refreshed.",
          description: response?.error ?? (
            <pre className="mt-2 rounded-md bg-slate-950 p-4">
              <code className="text-white text-xs">{JSON.stringify(response.data, null, 2)}</code>
            </pre>
          ) ?? "Statistical Units have been refreshed.",
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
                    <CommandItem onSelect={handleLegalUnitsReset}>
                        <Trash className="mr-2 h-4 w-4"/>
                        <span>Reset Legal Units</span>
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
