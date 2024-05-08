import { TableBody, TableCell, TableRow } from "@/components/ui/table";

export function SearchResultTableBodySkeleton() {
  return (
    <TableBody>
      {[...Array(10)].map((_, index) => (
        <TableRow key={index} className="animate-pulse">
          <TableCell className="py-2">
            <div className="flex items-center space-x-3">
              <div className="w-5 h-5 bg-gray-200" />
              <div className="flex flex-col space-y-1.5">
                <div className="flex w-56 h-4 lg:w-48 bg-gray-200" />
                <div className="flex w-20 h-3 lg:w-32 bg-gray-200" />
              </div>
            </div>
          </TableCell>
          <TableCell className="py-2 hidden lg:table-cell">
            <div className="flex flex-col space-y-1.5">
              <div className="flex w-16 h-4 bg-gray-200" />
              <div className="flex w-20 h-2.5 bg-gray-200" />
            </div>
          </TableCell>
          <TableCell />
          <TableCell />
          <TableCell className="py-2 hidden lg:table-cell">
            <div className="flex flex-col space-y-1.5">
              <div className="flex w-16 h-4 bg-gray-200" />
              <div className="flex w-28 h-2.5 bg-gray-200" />
            </div>
          </TableCell>
          <TableCell className="py-2 hidden lg:table-cell">
            <div className="flex  flex-col space-y-1.5">
              <div className="flex w-16 h-4 bg-gray-200" />
              <div className="flex w-36 h-2.5 bg-gray-200" />
            </div>
          </TableCell>
          <TableCell className="py-2">
            <div className="w-4 h-2 bg-gray-200" />
          </TableCell>
        </TableRow>
      ))}
    </TableBody>
  );
}
