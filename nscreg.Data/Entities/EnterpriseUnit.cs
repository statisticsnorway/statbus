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
        [Display(Order = 800)]
        public DateTime EntGroupIdDate { get; set; }    //	Date of assosciation with enterprise group
        [Display(Order = 380)]
        public bool Commercial { get; set; }  //	Indicator for non-commercial activity (marked/non-marked?)
        public string InstSectorCode { get; set; }  //	Institutional sector code (see Annex 3)
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        public string MunCapitalShare { get; set; } //	
        public string StateCapitalShare { get; set; }   //	
        public string PrivCapitalShare { get; set; }    //	
        public string ForeignCapitalShare { get; set; } //	
        public string ForeignCapitalCurrency { get; set; }  //	
        public string ActualMainActivity1 { get; set; } //	Main activity as perceived by the NSO using current version of classification
        public string ActualMainActivity2 { get; set; } //	Main activity as perceived by the NSO. To be used during transition to new activity classification version
        public string ActualMainActivityDate { get; set; } //	
        [Display(Order = 90)]
        public string EntGroupRole { get; set; }
        //	Role of enterprise within enterprise group (Management/control unit, global group head (controlling unit), Global decision centre (managing unit), highest level consolidation unit or “other”

        [Reference(LookupEnum.EnterpriseGroupLookup)]
        [Display(Order = 70)]
        public int? EntGroupId { get; set; } //	ID of enterprise group of which the unit belongs
        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 320)]
        public virtual ICollection<LegalUnit> LegalUnits { get; set; }

        [Reference(LookupEnum.LocalUnitLookup)]
        [Display(Order = 330)]
        public virtual ICollection<LocalUnit> LocalUnits { get; set; }
    }
}
