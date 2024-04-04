using System;
using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class InconsistentRecordValidator
    {
        private readonly Dictionary<StatUnitTypes, Action> _statUnitCheckByTypeDictionary;

        public InconsistentRecordValidator()
        {
            _statUnitCheckByTypeDictionary = new Dictionary<StatUnitTypes, Action>
            {
                [StatUnitTypes.LegalUnit] = LegalUnitChecks,
                [StatUnitTypes.LocalUnit] = LocalUnitChecks,
                [StatUnitTypes.EnterpriseUnit] = EnterpriseUnitChecks,
                [StatUnitTypes.EnterpriseGroup] = EnterpriseGroupChecks
            };
        }

        private IStatisticalUnit Record { get; set; }
        public List<string> Inaccuracies { get; private set; }

        public InconsistentRecord Specify(IStatisticalUnit record)
        {
            Inaccuracies = new List<string>();
            Record = record;
            CommonChecks();
            _statUnitCheckByTypeDictionary[Record.UnitType]();
            return new InconsistentRecord(Record.RegId, Record.UnitType, Record.Name, Inaccuracies);
        }

        private void LegalUnitChecks()
        {
            var unit = (LegalUnit) Record;
            if (unit.Activities.All(x => x.ActivityType != ActivityTypes.Primary)) Inaccuracies.Add(nameof(Resource.LogicalChecksNoMainActivity));
        }

        private void LocalUnitChecks()
        {
            var unit = (LocalUnit) Record;
            if (unit.LegalUnitId == 0) Inaccuracies.Add(nameof(Resource.LogicalChecksLocalNoLegal));
            if (unit.Activities.All(x => x.ActivityType != ActivityTypes.Primary)) Inaccuracies.Add(nameof(Resource.LogicalChecksNoMainActivity));
        }

        private void EnterpriseUnitChecks()
        {
            var unit = (EnterpriseUnit) Record;
            if (unit.LegalUnits.Count == 0)
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoOneLegalUnit));
            if (unit.Activities.All(x => x.ActivityType != ActivityTypes.Primary))
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoMainActivity));
        }

        private void EnterpriseGroupChecks()
        {
            var group = (EnterpriseGroup) Record;
            if (group.ContactPerson == null) Inaccuracies.Add(nameof(Resource.LogicalChecksNoContactPerson));
        }

        private void CommonChecks()
        {
            if (Record.ActualAddress == null)
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoAddress));
            if (Record.ActualAddress != null && (Record.ActualAddress.AddressPart1 == null || Record.ActualAddress.AddressPart2 == null))
                Inaccuracies.Add(nameof(Resource.LogicalChecksAddressTooFewInfo));
        }
    }
}
