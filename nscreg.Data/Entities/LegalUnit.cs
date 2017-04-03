using System;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class LegalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;
        [Display(Order = 200, GroupName = nameof(GroupName.RegistrationInfo))]
        public DateTime EntRegIdDate { get; set; }  //	Date of association with enterprise
        [Display(Order = 170, GroupName = nameof(GroupName.StatUnitInfo))]
        public string Founders { get; set; }    //	
        [Display(Order = 140, GroupName = nameof(GroupName.StatUnitInfo))]
        public string Owner { get; set; }   //	
        [Display(Order = 400, GroupName = nameof(GroupName.CapitalInfo))]
        public bool  Market { get; set; }  //	Whether the unit is market/non-market (In Kyrgyzstan this is probably whether it is self financed versus state budget financed..)
        [Display(Order = 180, GroupName = nameof(GroupName.RegistrationInfo))]
        public string LegalForm { get; set; }   //	legal form code
        [Display(Order = 190, GroupName = nameof(GroupName.StatUnitInfo))]
        public string InstSectorCode { get; set; }  //	Institutional sector code (see Annex 3)
        [Display(Order = 480, GroupName = nameof(GroupName.CapitalInfo))]
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        [Display(Order = 410, GroupName = nameof(GroupName.CapitalInfo))]
        public string MunCapitalShare { get; set; } //	
        [Display(Order = 420, GroupName = nameof(GroupName.CapitalInfo))]
        public string StateCapitalShare { get; set; }   //	
        [Display(Order = 430, GroupName = nameof(GroupName.CapitalInfo))]
        public string PrivCapitalShare { get; set; }    //	
        [Display(Order = 440, GroupName = nameof(GroupName.CapitalInfo))]
        public string ForeignCapitalShare { get; set; } //	
        [Display(Order = 450, GroupName = nameof(GroupName.CapitalInfo))]
        public string ForeignCapitalCurrency { get; set; }  //	
        [Display(Order = 200, GroupName = nameof(GroupName.ActivityInfo))]
        public string ActualMainActivity1 { get; set; } //	Main activity as perceived by the NSO using current version of classification
        [Display(Order = 220, GroupName = nameof(GroupName.ActivityInfo))]
        public string ActualMainActivity2 { get; set; } //	Main activity as perceived by the NSO. To be used during transition to new activity classification version
        [Display(Order = 210, GroupName = nameof(GroupName.ActivityInfo))]
        public string ActualMainActivityDate { get; set; }  //	
        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 100, GroupName = nameof(GroupName.LinkInfo))]
        public int? EnterpriseRegId { get; set; }    //	ID of Enterprise to which the Legal Unit is associated
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
        [Reference(LookupEnum.EnterpriseGroupLookup)]
        [Display(GroupName = nameof(GroupName.LinkInfo))]
        public int? EnterpriseGroupRegId { get; set; }    //	ID of EnterpriseGrop Legal Unit is associated with
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

    }
}
