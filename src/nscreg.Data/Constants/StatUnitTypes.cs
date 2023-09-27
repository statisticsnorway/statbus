using System;
using nscreg.Data.Entities;

namespace nscreg.Data.Constants
{
    /// <summary>
    /// Stat unit type constants
    /// </summary>
    public enum StatUnitTypes
    {
        LocalUnit = 1,
        LegalUnit = 2,
        EnterpriseUnit = 3,
        EnterpriseGroup = 4
    }
    public static class StatUnitTypesExtensions
    {
        public static StatUnitTypes GetStatUnitType(this IStatisticalUnit unit) =>
            unit switch
            {
                LocalUnit _ => StatUnitTypes.LocalUnit,
                LegalUnit _ => StatUnitTypes.LegalUnit,
                EnterpriseUnit _ => StatUnitTypes.EnterpriseUnit,
                EnterpriseGroup _ => StatUnitTypes.EnterpriseGroup,
                _ => throw new ArgumentOutOfRangeException(nameof(unit))
            };
        public static StatUnitTypes GetStatUnitType(this LocalUnit _) => StatUnitTypes.LocalUnit;
        public static StatUnitTypes GetStatUnitType(this LegalUnit _) => StatUnitTypes.LegalUnit;
        public static StatUnitTypes GetStatUnitType(this EnterpriseUnit _) => StatUnitTypes.EnterpriseUnit;
        public static StatUnitTypes GetStatUnitType(this EnterpriseGroup _) => StatUnitTypes.EnterpriseGroup;

    }

}
