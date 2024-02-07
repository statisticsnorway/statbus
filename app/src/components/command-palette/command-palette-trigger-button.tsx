'use client';
import {ArrowBigUp, Command} from "lucide-react";
import {Button} from "@/components/ui/button";

export default function CommandPaletteTriggerButton() {
    function showCommandPalette() {
        document.dispatchEvent(new CustomEvent('toggle-command-palette'))
    }

    return (
        <Button
            title="Open command palette"
            variant="ghost"
            size="sm"
            type="button"
            className="space-x-1 font-normal"
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
