using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    [Table("V_StatUnitSearch")]
    public class StatUnitSearchView
    {
        [Key]
        public int RegId { get; set; }
        public string Name { get; set; }
        public string StatId { get; set; }
        public string TaxRegId { get; set; }
        public string ExternalId { get; set; }
        public int? RegionId { get; set; }
        public decimal? Turnover { get; set; }
        public int? Employees { get; set; }
        public int? SectorCodeId { get; set; }
        public int? LegalFormId { get; set; }
        public string DataSource { get; set; }
        public DateTime StartPeriod { get; set; }
        public StatUnitTypes UnitType { get; set; }
        public int? ParentId { get; set; }
        public bool IsDeleted { get; set; }
        public string LiqReason { get; set; }
        public string AddressPart1 { get; set; }
        public string AddressPart2 { get; set; }
        public string AddressPart3 { get; set; }
    }
}
