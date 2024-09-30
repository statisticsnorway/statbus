"use client";

import { useEffect, useState } from "react";
import { NextResponse } from "next/server";

export default function SearchResults({ searchParams }: { searchParams: URLSearchParams }) {
  const [data, setData] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchData() {
      const response = await fetch(`/api/statistical-units?${searchParams}`);
      if (response.ok) {
        const statisticalUnits = await response.json();
        setData(statisticalUnits);
      }
      setLoading(false);
    }
    fetchData();
  }, [searchParams]);

  if (loading) {
    return <div>Loading...</div>; // Replace with a skeleton component if needed
  }

  return (
    <div>
      {data ? (
        <div>{/* Render your data here */}</div>
      ) : (
        <div>No data available</div>
      )}
    </div>
  );
}
