import {Button} from "@/components/ui/button";
import {PlusCircle} from "lucide-react";

interface TableFilterProps {
  title: string
}

export function TableFilter({title}: TableFilterProps) {
  return (
    <Button variant="outline" size="sm" className="border-dashed h-full">
      <PlusCircle className="mr-2 h-4 w-4"/>
      {title}
    </Button>
  )
}
