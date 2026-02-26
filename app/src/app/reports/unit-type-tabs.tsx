import { StatisticalUnitIcon } from "@/components/statistical-unit-icon";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";

export const unitTypeOptions: { value: UnitType; label: string; className: string }[] =
  [
    {
      value: "enterprise",
      label: "Enterprises",
      className:
        "data-[state=active]:bg-enterprise-100 hover:bg-enterprise-100 border-1 rounded-lg data-[state=active]:border-enterprise-400",
    },
    {
      value: "legal_unit",
      label: "Legal Units",
      className:
        "data-[state=active]:bg-legal_unit-100 hover:bg-legal_unit-100 border-1 rounded-lg data-[state=active]:border-legal_unit-400",
    },
    {
      value: "establishment",
      label: "Establishments",
      className:
        "data-[state=active]:bg-establishment-100 hover:bg-establishment-100 border-1 rounded-lg data-[state=active]:border-establishment-400",
    },
  ];

interface UnitTypeTabsProps {
  readonly value: UnitType;
  readonly onValueChange: (value: UnitType) => void;
}

export function UnitTypeTabs({
  value,
  onValueChange,
}: UnitTypeTabsProps) {
  return (
      <Tabs
        value={value}
        onValueChange={(value) => onValueChange(value as UnitType)}
        className="w-full"
      >
        <TabsList className=" gap-1 bg-background">
          {unitTypeOptions.map((unitType) => (
            <TabsTrigger
              key={unitType.value}
              value={unitType.value}
              className={`${unitType.className} flex items-center gap-1 rounded-lg bg-white px-2.5`}
            >
              <StatisticalUnitIcon type={unitType.value} className="h-4 w-4" />
              {unitType.label}
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
  );
}

export function getUnitTypeLabel(unitType: UnitType) {
  return unitTypeOptions.find((option) => option.value === unitType)?.label;
}
