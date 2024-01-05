"use client"

import * as React from "react"
import {resetSettings} from "@/app/_actions/resetSettings";
import {useToast} from "@/components/ui/use-toast";
import {X} from "lucide-react"

import {
    CommandDialog,
    CommandEmpty,
    CommandGroup,
    CommandInput,
    CommandItem,
    CommandList,
    CommandSeparator,
} from "@/components/ui/command"

export function AdminCommand() {
    const [open, setOpen] = React.useState(false)
    const {toast} = useToast()

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
        await resetSettings()
        toast({
            title: "Reset OK",
            description: "All settings have been reset to their default values.",
        })
    }

    return (
        <CommandDialog open={open} onOpenChange={setOpen}>
            <CommandInput placeholder="Type a command or search..."/>
            <CommandList>
                <CommandEmpty>No results found.</CommandEmpty>
                <CommandGroup heading="Admin tools">
                    <CommandItem onSelect={handleSettingsReset}>
                        <X className="mr-2 h-4 w-4"/>
                        <span>Reset settings</span>
                    </CommandItem>
                </CommandGroup>
                <CommandSeparator/>
            </CommandList>
        </CommandDialog>
    )
}
