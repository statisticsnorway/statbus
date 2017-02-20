using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Server.Validators;

namespace nscreg.Server.Models.StatUnits.Create
{
    public class LegalUnitCreateM : StatUnitModelBase
    {
        public int EnterpriseRegId { get; set; }
        [DataType(DataType.Date)]
        public DateTime EntRegIdDate { get; set; }
        public string Founders { get; set; }
        public string Owner { get; set; }
        public bool Market { get; set; }
        public string LegalForm { get; set; }
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
    }


    //TODO: when we will know validation fields, we will use this validator for write rules (this is example of usage)
    public class LegalUnitCreateMValidator : StatUnitModelBaseValidator<LegalUnitCreateM>
    {
    }
}
