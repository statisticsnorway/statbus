import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

const data = [
  {
    id: "2014",
    name: "Establishments in 2014",
    data: [120, 130, 125, 135, 140, 145, 150, 155, 160, 165, 170, 175],
  },
  {
    id: "2015",
    name: "Establishments in 2015",
    data: [180, 185, 180, 175, 170, 165, 160, 155, 150, 145, 140, 135],
  },
  {
    id: "2016",
    name: "Establishments in 2016",
    data: [130, 135, 140, 145, 150, 155, 160, 165, 170, 175, 180, 185],
  },
  {
    id: "2017",
    name: "Establishments in 2017",
    data: [190, 185, 180, 175, 170, 165, 160, 155, 150, 145, 140, 135],
  },
  {
    id: "2018",
    name: "Establishments in 2018",
    data: [130, 135, 130, 125, 120, 115, 110, 105, 100, 95, 90, 85],
  },
  {
    id: "2019",
    name: "Establishments in 2019",
    data: [90, 95, 100, 105, 110, 115, 120, 125, 130, 135, 140, 145],
  },
  {
    id: "2020",
    name: "Establishments in 2020",
    data: [150, 155, 160, 165, 170, 175, 180, 185, 190, 195, 200, 205],
  },
  {
    id: "2021",
    name: "Establishments in 2021",
    data: [210, 205, 200, 195, 190, 185, 180, 175, 170, 165, 160, 155],
  },
  {
    id: "2022",
    name: "Establishments in 2022",
    data: [150, 155, 160, 165, 170, 160, 150, 140, 130, 120, 110, 100],
  },
  {
    id: "2023",
    name: "Establishments in 2023",
    data: [100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210],
  },
  {
    id: "2024",
    name: "Establishments in 2024",
    data: [215, 210, 205, 200, 195, 190, 185, 180, 175, 170, 165, 160],
  },
];

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const client = createClient();

  const year = searchParams.get("year");

  const history = await client
    .from("statistical_history")
    .select("count(),primary_activity_category_path")
    .eq("year", year);
  console.log(history.data);
  const mappedHistoryData = history.data?.map(
    // @ts-ignore
    ({ count, primary_activity_category_path }) => ({
      name: primary_activity_category_path,
      y: count,
    })
  );
  return NextResponse.json(mappedHistoryData);
}
