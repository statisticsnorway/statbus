import { Button } from "@/components/ui/button";
import { ArrowRight } from "lucide-react";
import { DrillDownPoint } from "@/app/reports/types/drill-down";

interface BreadCrumbProps {
  readonly topLevelText?: string;
  readonly points: DrillDownPoint[] | null;
  readonly selected: DrillDownPoint | null;
  readonly onSelect: (point: DrillDownPoint | null) => void;
}

export const BreadCrumb = ({
  points,
  selected = null,
  onSelect,
  topLevelText = "Show All",
}: BreadCrumbProps) => {
  return (
    <div className="flex flex-wrap">
      <Button
        size="sm"
        variant="ghost"
        className={!selected ? "underline" : ""}
        onClick={() => onSelect(null)}
      >
        {topLevelText}
      </Button>
      {points?.map((point) => (
        <div className="flex items-center space-x-2" key={point.path}>
          <ArrowRight size={18} />
          <Button
            size="sm"
            variant="ghost"
            className={point.path === selected?.path ? "underline" : ""}
            onClick={() => onSelect(point)}
          >
            {`${point.path} - ${point.name}`}
          </Button>
        </div>
      ))}
    </div>
  );
};
