using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.StatUnits.Base;

namespace nscreg.Server.Models.StatUnits.Edit
{
    public class EnterpriseUnitEditM : StatUnitCreateEditBaseM
    {
        [Required]
        public int? RegId { get; set; }
        public int? EntGroupId { get; set; }
        [DataType(DataType.Date)]
        public DateTime EntGroupIdDate { get; set; }
        public bool Commercial { get; set; }
        public string InstSectorCode { get; set; }
        public string TotalCapital { get; set; }
        public string MunCapitalShare { get; set; }
        public string StateCapitalShare { get; set; }
        public string PrivCapitalShare { get; set; }
        public string ForeignCapitalShare { get; set; }
        public string ForeignCapitalCurrency { get; set; }
        public string ActualMainActivity1 { get; set; }
        public string ActualMainActivity2 { get; set; }
        public string ActualMainActivityDate { get; set; }
        public string EntGroupRole { get; set; }
        public int[] LocalUnits { get; set; } 
        public int[] LegalUnits { get; set; }
    }
}
