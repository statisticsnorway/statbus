'use client';
import {ArrowBigUp, Command} from "lucide-react";
import {Button} from "@/components/ui/button";
import {cn} from "@/lib/utils";

export default function CommandPaletteTriggerButton({className}: { readonly className?: string }) {
    function showCommandPalette() {
        document.dispatchEvent(new CustomEvent('toggle-command-palette'))
    }

    return (
        <Button
            title="Open command palette"
            variant="outline"
            size="sm"
            type="button"
            className={cn("space-x-1 font-normal", className)}
            onClick={showCommandPalette}
        >
            <span>Command Palette</span>
            <span>(</span>
            <Command size={14}/>
            <span>+</span>
            <ArrowBigUp size={18}/>
            <span>+</span>
            <span>K</span>
            <span>)</span>
        </Button>
    )
}
