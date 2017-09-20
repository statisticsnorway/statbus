using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Common.Validators;

namespace nscreg.Server.Common.Models.StatUnits.Create
{
    public class LocalUnitCreateM : StatUnitModelBase
    {
        public int? LegalUnitId { get; set; }
        [DataType(DataType.Date)]
        public DateTime LegalUnitIdDate { get; set; }
    }

    public class LocalUnitCreateMValidator : StatUnitModelBaseValidator<LocalUnitCreateM>
    {
    }
}
