import {Button} from "@/components/ui/button";
import {Save} from "lucide-react";
import {HTMLProps} from "react";

interface SaveSearchButtonProps extends HTMLProps<HTMLButtonElement> {
}

export default function SaveSearchButton({ref, ...rest}: SaveSearchButtonProps) {
  return (
    <Button {...rest} type="button" size="sm" variant="secondary" className="flex items-center space-x-2">
      <Save size={17}/>
      <span>Save Search</span>
    </Button>
  )
}
