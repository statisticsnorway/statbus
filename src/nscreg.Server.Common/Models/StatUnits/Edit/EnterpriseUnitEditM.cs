using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Validators;

namespace nscreg.Server.Common.Models.StatUnits.Edit
{
    public class EnterpriseUnitEditM : StatUnitModelBase
    {
        [Required]
        public int? RegId { get; set; }
        public int? EntGroupId { get; set; }
        [DataType(DataType.Date)]
        public DateTime EntGroupIdDate { get; set; }
        public bool Commercial { get; set; }
        public int? InstSectorCodeId { get; set; }
        public string TotalCapital { get; set; }
        public string MunCapitalShare { get; set; }
        public string StateCapitalShare { get; set; }
        public string PrivCapitalShare { get; set; }
        public string ForeignCapitalShare { get; set; }
        public string ForeignCapitalCurrency { get; set; }
        public int? EntGroupRoleId { get; set; }
        public int[] LegalUnits { get; set; }
    }

    public class EnterpriseUnitEditMValidator : StatUnitModelBaseValidator<EnterpriseUnitEditM>
    {
    }
}
