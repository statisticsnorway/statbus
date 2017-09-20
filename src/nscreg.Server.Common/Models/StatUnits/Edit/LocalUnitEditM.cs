using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Validators;

namespace nscreg.Server.Common.Models.StatUnits.Edit
{
    public class LocalUnitEditM : StatUnitModelBase
    {
        [Required]
        public int? RegId { get; set; }
        public int? LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }

    public class LocalUnitEditMValidator : StatUnitModelBaseValidator<LocalUnitEditM>
    {
    }
}
