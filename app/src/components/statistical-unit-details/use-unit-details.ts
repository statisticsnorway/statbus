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
import { useSWRWithAuthRefresh, isJwtExpiredError, JwtExpiredError } from "@/hooks/use-swr-with-auth-refresh";

export function useStatisticalUnitDetails(id: string, unitType: UnitType) {
  const { selectedTimeContext } = useTimeContext();
  const validOn = selectedTimeContext?.valid_on;

  const { data, isLoading, error, mutate } = useSWRWithAuthRefresh(
    validOn ? ["details", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]: [string, string, UnitType, string]) => {
      const { unit, error } = await getStatisticalUnitDetails(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return unit;
    },
    {
      revalidateOnFocus: false,
    },
    "useStatisticalUnitDetails"
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

  const { data, isLoading, error, mutate } = useSWRWithAuthRefresh(
    validOn ? ["stats", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]: [string, string, UnitType, string]) => {
      const { stats, error } = await getStatisticalUnitStats(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return stats;
    },
    {
      revalidateOnFocus: false,
    },
    "useStatisticalUnitStats"
  );

  const unitStats = data?.find(
    (s) => s.unit_type === unitType && s.unit_id === parseInt(id, 10)
  ) as StatisticalUnitStats | undefined;

  return {
    data: unitStats,
    isLoading: isLoading || !validOn,
    revalidate: () => mutate(),
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

  const { data, isLoading, error } = useSWRWithAuthRefresh(
    validOn && !compact ? ["stats", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]: [string, string, UnitType, string]) => {
      const { stats, error } = await getStatisticalUnitStats(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return stats;
    },
    {
      revalidateOnFocus: false,
    },
    "useStatisticalUnitHierarchyStats"
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

  const { data, isLoading, error, mutate } = useSWRWithAuthRefresh(
    validOn ? ["hierarchy", id, unitType, validOn] : null,
    async ([, id, unitType, validOn]: [string, string, UnitType, string]) => {
      const { hierarchy, error } = await getStatisticalUnitHierarchy(
        parseInt(id, 10),
        unitType,
        validOn
      );
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return hierarchy;
    },
    {
      revalidateOnFocus: false,
    },
    "useStatisticalUnitHierarchy"
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

  const { data, isLoading, error } = useSWRWithAuthRefresh(
    validOn ? ["legal_unit", id, validOn] : null,
    async ([, id, validOn]: [string, string, string]) => {
      const { legalUnit, error } = await getLegalUnitById(id, validOn);
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return legalUnit;
    },
    {
      revalidateOnFocus: false,
    },
    "useLegalUnit"
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

  const { data, isLoading, error } = useSWRWithAuthRefresh(
    validOn ? ["establishment", id, validOn] : null,
    async ([, id, validOn]: [string, string, string]) => {
      const { establishment, error } = await getEstablishmentById(id, validOn);
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return establishment;
    },
    {
      revalidateOnFocus: false,
    },
    "useEstablishment"
  );

  return {
    establishment: data,
    isLoading: isLoading || !validOn,
    error,
  };
}

export function useEnterprise(id: string) {
  const { data, isLoading, error } = useSWRWithAuthRefresh(
    ["enterprise", id],
    async ([, id]: [string, string]) => {
      const { enterprise, error } = await getEnterpriseById(id);
      if (error) {
        if (isJwtExpiredError(error)) throw new JwtExpiredError();
        throw error;
      }
      return enterprise;
    },
    {
      revalidateOnFocus: false,
    },
    "useEnterprise"
  );

  return {
    enterprise: data,
    isLoading: isLoading,
    error,
  };
}
