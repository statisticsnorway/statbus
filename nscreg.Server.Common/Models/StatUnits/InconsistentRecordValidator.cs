using System;
using System.Collections.Generic;
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
            if (unit.Owner == null) Inaccuracies.Add(nameof(Resource.LogicalChecksNoOwner));
            if (unit.RegMainActivity == null) Inaccuracies.Add(nameof(Resource.LogicalChecksNoMainActivity));
        }

        private void LocalUnitChecks()
        {
            var unit = (LocalUnit) Record;
            if (unit.LegalUnitId == 0) Inaccuracies.Add(nameof(Resource.LogicalChecksLocalNoLegal));
            if (unit.RegMainActivity == null) Inaccuracies.Add(nameof(Resource.LogicalChecksNoMainActivity));
        }

        private void EnterpriseUnitChecks()
        {
            var unit = (EnterpriseUnit) Record;
            if (unit.LegalUnits.Count == 0)
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoOneLegalUnit));
            if (unit.LocalUnits.Count == 0)
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoOneLocalUnit));
            if (unit.RegMainActivity == null)
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoMainActivity));
        }

        private void EnterpriseGroupChecks()
        {
            var group = (EnterpriseGroup) Record;
            if (group.ContactPerson == null) Inaccuracies.Add(nameof(Resource.LogicalChecksNoContactPerson));
        }

        private void CommonChecks()
        {
            if (Record.Address == null)
                Inaccuracies.Add(nameof(Resource.LogicalChecksNoAddress));
            if (Record.Address != null && (Record.Address.AddressPart1 == null || Record.Address.AddressPart2 == null))
                Inaccuracies.Add(nameof(Resource.LogicalChecksAddressTooFewInfo));
        }
    }
}