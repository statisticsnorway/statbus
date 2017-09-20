using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class LegalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;
        [Display(Order = 200, GroupName =GroupNames.RegistrationInfo)]
        public DateTime EntRegIdDate { get; set; }  //	Date of association with enterprise
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string Founders { get; set; }    //	
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string Owner { get; set; }   //	
        [Display(Order = 400, GroupName =GroupNames.CapitalInfo)]
        public bool  Market { get; set; }  //	Whether the unit is market/non-market (In Kyrgyzstan this is probably whether it is self financed versus state budget financed..)
        [Display(Order = 180, GroupName = GroupNames.RegistrationInfo)]
        [Reference(LookupEnum.LegalFormLookup)]
        public override int? LegalFormId
        {
            get => base.LegalFormId;
            set => base.LegalFormId = value;
        }   //	legal form code
        [Display(Order = 190, GroupName = GroupNames.StatUnitInfo)]
        [Reference(LookupEnum.SectorCodeLookup)]
        public override int? InstSectorCodeId
        {
            get => base.InstSectorCodeId;
            set => base.InstSectorCodeId = value;
        }    //	Institutional sector code (see Annex 3)
        [Display(Order = 480, GroupName =GroupNames.CapitalInfo)]
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        [Display(Order = 410, GroupName =GroupNames.CapitalInfo)]
        public string MunCapitalShare { get; set; } //	
        [Display(Order = 420, GroupName =GroupNames.CapitalInfo)]
        public string StateCapitalShare { get; set; }   //	
        [Display(Order = 430, GroupName =GroupNames.CapitalInfo)]
        public string PrivCapitalShare { get; set; }    //	
        [Display(Order = 440, GroupName =GroupNames.CapitalInfo)]
        public string ForeignCapitalShare { get; set; } //	
        [Display(Order = 450, GroupName =GroupNames.CapitalInfo)]
        public string ForeignCapitalCurrency { get; set; }  //	
        [Reference(LookupEnum.EnterpriseUnitLookup)]
        [Display(Order = 100, GroupName =GroupNames.LinkInfo)]
        public int? EnterpriseUnitRegId { get; set; }    //	ID of Enterprise to which the Legal Unit is associated
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
        [Reference(LookupEnum.LocalUnitLookup)]
        [Display(GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<LocalUnit> LocalUnits { get; set; } = new HashSet<LocalUnit>();
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public string HistoryLocalUnitIds { get; set; }

    }
}
