"use client"

import * as React from "react"
import {resetSettings} from "@/app/_actions/resetSettings";
import {resetRegions} from "@/app/_actions/resetRegions";
import {useToast} from "@/components/ui/use-toast";
import {useRouter} from "next/navigation";
import {Footprints, Home, Trash, User} from "lucide-react"

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
  const [open, setOpen] = React.useState(false)
  const {toast} = useToast()
  const router = useRouter()

  React.useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if (e.key === "k" && (e.metaKey || e.ctrlKey) && e.shiftKey) {
        e.preventDefault()
        setOpen((open) => !open)
      }
    }

    document.addEventListener("keydown", down)
    return () => document.removeEventListener("keydown", down)
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
            <span>Reset settings</span>
          </CommandItem>
          <CommandItem onSelect={handleRegionsReset}>
            <Trash className="mr-2 h-4 w-4"/>
            <span>Reset regions</span>
          </CommandItem>
        </CommandGroup>
        <CommandSeparator/>
        <CommandGroup heading="Pages">
          <CommandItem onSelect={() => navigate("/getting-started")}>
            <Footprints className="mr-2 h-4 w-4"/>
            <span>Getting started</span>
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
