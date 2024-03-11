import { Pagination, PaginationContent,
    PaginationItem,
    PaginationNext,
    PaginationPrevious, PaginationFirst, PaginationLast } from "@/components/ui/pagination";
import { useSearchContext } from "../search-provider";


export default function SearchResultPagination() {
    const { search: {page}, dispatch, searchResult } = useSearchContext();
    const totalResults = searchResult?.count || 0
    const totalPages = Math.ceil(totalResults / page.size)

    const handlePageChange = (newPage : number) => {
      dispatch({ type: 'set_page', payload: { value: newPage } });
    };

    if(!totalResults) return null;

  return (
    <Pagination>
      <PaginationContent>
        <PaginationItem>
          <PaginationFirst 
            disabled={page.value == 1}  
            onClick={() => handlePageChange(1)}/>
        </PaginationItem>
        <PaginationItem>
          <PaginationPrevious
            disabled={page.value == 1}
            onClick={() => handlePageChange(page.value - 1)}
          />
        </PaginationItem>
        <span className="px-1">
            Page {page.value} of {totalPages}
        </span>
        <PaginationItem>
          <PaginationNext
            disabled={page.value == totalPages}
            onClick={() => handlePageChange(page.value + 1)}
          />
        </PaginationItem>
        <PaginationItem>
          <PaginationLast 
            disabled={page.value == totalPages}  
            onClick={() => handlePageChange(totalPages)}/>
        </PaginationItem>
      </PaginationContent>
    </Pagination>
  );
};
