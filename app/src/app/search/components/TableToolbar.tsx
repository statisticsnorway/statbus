import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";

interface TableToolbarProps {
  readonly onSearch: (search: string) => void
}

export default function TableToolbar({onSearch}: TableToolbarProps) {
  return (
    <div className="w-full items-center space-y-3 bg-green-100 p-4">
      <div className="flex justify-between">
        <Label htmlFor="search-prompt">Find units by name or ID</Label>
      </div>
      <Input
        type="text"
        id="search-prompt"
        placeholder="Legal Unit"
        onChange={(e) => onSearch(e.target.value)}
      />
    </div>
  )
}
