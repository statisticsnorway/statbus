import {Label} from "@/components/ui/label";
import {Input} from "@/components/ui/input";
import {Button} from "@/components/ui/button";
import {uploadRegions} from "@/app/getting-started/upload-regions/actions";

export default async function Home() {
  return (
    <form action={uploadRegions} className="space-y-6">
      <Label className="text-lg block" htmlFor="regions-file">Select regions file</Label>
      <Input required id="regions-file" type="file" name="regions" />
      <Button type="submit">Next</Button>
    </form>
  )
}
