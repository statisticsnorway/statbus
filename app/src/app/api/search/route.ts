import { Suspense } from "react";
 import SearchResults from "@/app/search/SearchResults";

 export default function SearchPage({ searchParams }: { searchParams: URLSearchParams }) {
   return (
     <Suspense fallback={<div>Loading...</div>}>
       <SearchResults searchParams={searchParams} />
     </Suspense>
   );
 }