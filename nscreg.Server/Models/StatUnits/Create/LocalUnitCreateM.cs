using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Validators;

namespace nscreg.Server.Models.StatUnits.Create
{
    public class LocalUnitCreateM : StatUnitModelBase
    {
        public int? LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
        public int? EnterpriseUnitRegId { get; set; }
    }

    public class LocalUnitCreateMValidator : StatUnitModelBaseValidator<LocalUnitCreateM>
    {
    }
}
