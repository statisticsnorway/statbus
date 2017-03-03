using System;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class LegalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;
        public DateTime EntRegIdDate { get; set; }  //	Date of association with enterprise
        public string Founders { get; set; }    //	
        public string Owner { get; set; }   //	
        public bool  Market { get; set; }  //	Whether the unit is market/non-market (In Kyrgyzstan this is probably whether it is self financed versus state budget financed..)
        public string LegalForm { get; set; }   //	legal form code
        public string InstSectorCode { get; set; }  //	Institutional sector code (see Annex 3)
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        public string MunCapitalShare { get; set; } //	
        public string StateCapitalShare { get; set; }   //	
        public string PrivCapitalShare { get; set; }    //	
        public string ForeignCapitalShare { get; set; } //	
        public string ForeignCapitalCurrency { get; set; }  //	
        public string ActualMainActivity1 { get; set; } //	Main activity as perceived by the NSO using current version of classification
        public string ActualMainActivity2 { get; set; } //	Main activity as perceived by the NSO. To be used during transition to new activity classification version
        public string ActualMainActivityDate { get; set; }  //	
        [Reference(LookupEnum.EnterpriseUnitLookup)]
        public int? EnterpriseRegId { get; set; }    //	ID of Enterprise to which the Legal Unit is associated
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
        [Reference(LookupEnum.EnterpriseGroupLookup)]
        public int? EnterpriseGroupRegId { get; set; }    //	ID of EnterpriseGrop Legal Unit is associated with
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

    }
}
