using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Extensions;

namespace nscreg.Business.Analysis.StatUnit
{
    /// <summary>
    /// Stat unit analyzer
    /// </summary>
    public class StatUnitAnalyzer : IStatUnitAnalyzer
    {
        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckConnections"/>
        /// </summary>
        public Dictionary<int, Dictionary<string, string[]>> CheckConnections(IStatisticalUnit unit,
            bool isAnyRelatedLegalUnit, bool isAnyRelatedActivities, List<Address> addresses)
        {
            var messages = new Dictionary<string, string[]>();

            if (unit.UnitType != StatUnitTypes.LegalUnit)
            {
                if (!isAnyRelatedLegalUnit)
                    messages.Add("LegalUnit", new[] { "Stat unit doesn't have related legal unit" });

                if (!isAnyRelatedActivities)
                    messages.Add("Activity", new[] { "Stat unit doesn't have related activity" });
            }

            if (addresses.All(a => a.AddressPart1 != unit.Address.AddressPart1 && a.RegionId != unit.Address.RegionId))
                messages.Add("Address", new[] { "Stat unit doesn't have related address" });

            var result = new Dictionary<int, Dictionary<string, string[]>>();

            if (messages.Any()) result.Add(unit.RegId, messages);

            return result;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckMandatoryFields"/>
        /// </summary>
        public Dictionary<int, Dictionary<string, string[]>> CheckMandatoryFields(IStatisticalUnit unit)
        {
            var messages = new Dictionary<string, string[]>();

            if (string.IsNullOrEmpty(unit.DataSource))
                messages.Add(nameof(unit.DataSource), new[] { "Stat unit doesn't have data source" });

            if (string.IsNullOrEmpty(unit.Name))
                messages.Add(nameof(unit.Name), new[] { "Stat unit doesn't have name" });

            if (unit.UnitType != StatUnitTypes.EnterpriseGroup)
            {
                var statUnit = (StatisticalUnit)unit;
                if (string.IsNullOrEmpty(statUnit.ShortName))
                    messages.Add(nameof(statUnit.ShortName), new[] { "Stat unit doesn't have short name" });
                else if (statUnit.ShortName == statUnit.Name)
                    messages.Add(nameof(unit.Name), new[] { "Stat unit's short name is the same as name" });

                if (statUnit.Address is null)
                    messages.Add(nameof(statUnit.Name), new[] { "Stat unit doesn't have address" });

                if (string.IsNullOrEmpty(statUnit.TelephoneNo))
                    messages.Add(nameof(statUnit.Name), new[] { "Stat unit doesn't have telephone number" });

                if (string.IsNullOrEmpty(statUnit.RegistrationReason))
                    messages.Add(nameof(statUnit.Name), new[] { "Stat unit doesn't have registration reason" });

                if (string.IsNullOrEmpty(statUnit.ContactPerson))
                    messages.Add(nameof(statUnit.Name), new[] { "Stat unit doesn't have contact person" });

                if (statUnit.Status != StatUnitStatuses.Active)
                    messages.Add(nameof(unit.Name), new[] { "Stat unit's status is not \"active\"" });
            }

            if (unit.UnitType == StatUnitTypes.LegalUnit && ((LegalUnit)unit).PersonsUnits.All(pu => pu.PersonType != PersonTypes.Owner))
                messages.Add(nameof(unit.Name), new[] { "Legal unit doesn't have any person with \"Owner\" status" });

            var result = new Dictionary<int, Dictionary<string, string[]>>();

            if (messages.Any()) result.Add(unit.RegId, messages);

            return result;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckOrphanUnits"/>
        /// </summary>
        public Dictionary<int, Dictionary<string, string[]>> CheckOrphanUnits(IStatisticalUnit unit)
        {
            var enterpriseUnit = (EnterpriseUnit)unit;
            var result = new Dictionary<int, Dictionary<string, string[]>>();
            var messages = new Dictionary<string, string[]>();
            if (enterpriseUnit.EntGroupId == null)
                messages.Add("Activity", new[] { "Stat unit doesn't have related activity" });

            if (messages.Any()) result.Add(enterpriseUnit.RegId, messages);
            return result;
        }

        /// <summary>
        /// <see cref="IStatUnitAnalyzer.CheckAll"/>
        /// </summary>
        public Dictionary<int, Dictionary<string, string[]>> CheckAll(IStatisticalUnit unit, bool isAnyRelatedLegalUnit,
            bool isAnyRelatedActivities, List<Address> addresses)
        {
            var messages = new Dictionary<int, Dictionary<string, string[]>>();

            messages.AddRange(CheckConnections(unit, isAnyRelatedLegalUnit, isAnyRelatedActivities, addresses));
            messages.AddRange(CheckMandatoryFields(unit));
            if (unit.UnitType == StatUnitTypes.EnterpriseUnit)
                messages.AddRange(CheckOrphanUnits(unit));

            return messages;
        }
    }
}
