using System;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Helpers
{
    public class StatUnitSearchHelper
    {
        public StatUnitSearchHelper(IStatisticalUnit unit)
        {
            Address = unit.Address;
        }
        public int RegId { get; set; }
        public string Name { get; set; }
        public string StatId { get; set; }
        public string TaxRegId { get; set; }
        public string ExternalId { get; set; }
        public Address Address { get; set; }
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public Region Region { get; set; }
        public decimal? Turnover { get; set; }
        public int? Employees { get; set; }
        public int? SectorCodeId { get; set; }
        public int? LegalFormId { get; set; }
        public string DataSource { get; set; }
        public DateTime StartPeriod { get; set; }
        public StatUnitTypes UnitType { get; set; }
    }
}
