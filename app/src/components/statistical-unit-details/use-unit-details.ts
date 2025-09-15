"use client";
import useSWR from "swr";
import {
  getEnterpriseById,
  getEstablishmentById,
  getLegalUnitById,
  getStatisticalUnitDetails,
  getStatisticalUnitHierarchy,
  getStatisticalUnitStats,
} from "@/components/statistical-unit-details/requests";
import { useTimeContext } from "@/atoms/app-derived";

export function useStatisticalUnitDetails(id: string, unitType: UnitType) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error, mutate } = useSWR(
    validOn ? ["details", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]) => {
      const { unit, error } = await getStatisticalUnitDetails(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) throw error;
      return unit;
    },
    {
      revalidateOnFocus: false,
    }
  );

  return {
    data,
    isLoading: isLoading || !validOn,
    revalidate: () => mutate(),
    error,
  };
}

export function useStatisticalUnitStats(id: string, unitType: UnitType) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error } = useSWR(
    validOn ? ["stats", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]) => {
      const { stats, error } = await getStatisticalUnitStats(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) throw error;
      return stats;
    },
    {
      revalidateOnFocus: false,
    }
  );

  const unitStats = data?.find(
    (s) => s.unit_type === unitType && s.unit_id === parseInt(id, 10)
  ) as StatisticalUnitStats | undefined;

  return {
    data: unitStats,
    isLoading: isLoading || !validOn,
    error,
  };
}

export function useStatisticalUnitHierarchyStats(
  id: string,
  unitType: UnitType,
  compact: boolean
) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error } = useSWR(
    validOn && !compact ? ["stats", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]) => {
      const { stats, error } = await getStatisticalUnitStats(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) throw error;
      return stats;
    },
    {
      revalidateOnFocus: false,
    }
  );

  return {
    data,
    isLoading: isLoading || !validOn,
    error,
  };
}

export function useStatisticalUnitHierarchy(id: string, unitType: UnitType) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error, mutate } = useSWR(
    validOn ? ["hierarchy", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]) => {
      const { hierarchy } = await getStatisticalUnitHierarchy(
        parseInt(id, 10),
        unitType,
        validOn
      );
      return hierarchy;
    },
    {
      revalidateOnFocus: false,
    }
  );

  return {
    hierarchy: data,
    isLoading: isLoading || !validOn,
    revalidate: () => mutate(),
    error,
  };
}

export function useLegalUnit(id: string) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error } = useSWR(
    validOn ? ["legal_unit", id, validOn] : null,
    async ([, id, validOn]) => {
      const { legalUnit, error } = await getLegalUnitById(id, validOn);
      if (error) throw error;
      return legalUnit;
    },
    {
      revalidateOnFocus: false,
    }
  );

  return {
    legalUnit: data,
    isLoading: isLoading || !validOn,
    error,
  };
}

export function useEstablishment(id: string) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error } = useSWR(
    validOn ? ["establishment", id, validOn] : null,
    async ([, id, validOn]) => {
      const { establishment, error } = await getEstablishmentById(id, validOn);
      if (error) throw error;
      return establishment;
    },
    {
      revalidateOnFocus: false,
    }
  );

  return {
    establishment: data,
    isLoading: isLoading || !validOn,
    error,
  };
}

export function useEnterprise(id: string) {
  const { data, isLoading, error } = useSWR(
    ["enterprise", id],
    async ([, id]) => {
      const { enterprise, error } = await getEnterpriseById(id);
      if (error) throw error;
      return enterprise;
    },
    {
      revalidateOnFocus: false,
    }
  );

  return {
    enterprise: data,
    isLoading: isLoading,
    error,
  };
}
