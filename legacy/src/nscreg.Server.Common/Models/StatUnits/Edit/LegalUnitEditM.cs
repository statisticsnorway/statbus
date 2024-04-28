using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Validators;

namespace nscreg.Server.Common.Models.StatUnits.Edit
{
    public class LegalUnitEditM : StatUnitModelBase
    {
        [Required]
        public int? RegId { get; set; }

        public int? EnterpriseRegId { get; set; }

        [DataType(DataType.Date)]
        public DateTimeOffset EntRegIdDate { get; set; }

        public bool Market { get; set; }
        public int? LegalFormId { get; set; }
        public int? InstSectorCodeId { get; set; }
        public string TotalCapital { get; set; }
        public string MunCapitalShare { get; set; }
        public string StateCapitalShare { get; set; }
        public string PrivCapitalShare { get; set; }
        public string ForeignCapitalShare { get; set; }
        public string ForeignCapitalCurrency { get; set; }
        public int? EnterpriseUnitRegId { get; set; }
        public int[] LocalUnits { get; set; }
    }

    public class LegalUnitEditMValidator : StatUnitModelBaseValidator<LegalUnitEditM>
    {
    }
}
