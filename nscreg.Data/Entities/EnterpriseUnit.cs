using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class EnterpriseUnit : StatisticalUnit
    {
        public EnterpriseUnit()
        {
            LegalUnits = new HashSet<LegalUnit>();
            LocalUnits = new HashSet<LocalUnit>();
        }

        public override StatUnitTypes UnitType => StatUnitTypes.EnterpriseUnit;
        [Display(Order = 800, GroupName = GroupNames.RegistrationInfo)]
        public DateTime EntGroupIdDate { get; set; }    //	Date of assosciation with enterprise group
        [Display(Order = 380, GroupName = GroupNames.RegistrationInfo)]
        public bool Commercial { get; set; }  //	Indicator for non-commercial activity (marked/non-marked?)
        [Display(GroupName = GroupNames.StatUnitInfo)]
        public int? InstSectorCodeId { get; set; }  //	Institutional sector code (see Annex 3)
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual SectorCode InstSectorCode { get; set; }
        [Display (GroupName = GroupNames.CapitalInfo)]
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string MunCapitalShare { get; set; } //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string StateCapitalShare { get; set; }   //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string PrivCapitalShare { get; set; }    //	
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalShare { get; set; } //
        [Display(GroupName = GroupNames.CapitalInfo)]
        public string ForeignCapitalCurrency { get; set; }  //	
        [Display(GroupName = GroupNames.LinkInfo)]
        public string ActualMainActivity1 { get; set; } //	Main activity as perceived by the NSO using current version of classification
        [Display(GroupName = GroupNames.LinkInfo)]
        public string ActualMainActivity2 { get; set; } //	Main activity as perceived by the NSO. To be used during transition to new activity classification version
        [Display(GroupName = GroupNames.LinkInfo)]
        public string ActualMainActivityDate { get; set; } //	
        [Display(Order = 90, GroupName = GroupNames.StatUnitInfo)]
        public string EntGroupRole { get; set; }
        //	Role of enterprise within enterprise group (Management/control unit, global group head (controlling unit), Global decision centre (managing unit), highest level consolidation unit or “other”

        [Reference(LookupEnum.EnterpriseGroupLookup)]
        [Display(Order = 70, GroupName = GroupNames.LinkInfo)]
        public int? EntGroupId { get; set; } //	ID of enterprise group of which the unit belongs
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 320, GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; }

        [Reference(LookupEnum.LocalUnitLookup)]
        [Display(Order = 330, GroupName = GroupNames.LinkInfo)]
        public virtual ICollection<LocalUnit> LocalUnits { get; set; }
    }
}
