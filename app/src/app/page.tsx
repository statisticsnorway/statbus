import {Table, TableBody, TableCell, TableHead, TableHeader, TableRow} from "@/components/ui/table";
import {InfoBox} from "@/components/InfoBox";
import {createClient} from "@/lib/supabase/server";

export default async function Home() {
  const client = createClient();
  const { data: legalUnits, error } = await client.from('legal_unit').select('*').limit(10);
  return (
    <main className="flex flex-col p-8 md:p-24 space-y-6 max-w-7xl mx-auto">
      <h1 className="font-medium text-lg">Welcome to Statbus!</h1>

      <InfoBox>
        <p>Search is coming soon!</p>
      </InfoBox>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead className="w-[100px]">ID</TableHead>
            <TableHead>Name</TableHead>
            <TableHead>Employees</TableHead>
            <TableHead className="text-right">Region</TableHead>
            <TableHead className="text-right">Activity Category Code</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {
            legalUnits?.map((legalUnit) => (
              <TableRow key={legalUnit.tax_reg_ident}>
                <TableCell className="font-medium">{legalUnit.tax_reg_ident}</TableCell>
                <TableCell>{legalUnit.name}</TableCell>
                <TableCell>N/A</TableCell>
                <TableCell className="text-right">N/A</TableCell>
                <TableCell className="text-right">N/A</TableCell>
              </TableRow>
            ))
          }
        </TableBody>
      </Table>
    </main>
  )
}
