using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность местная еденица
    /// </summary>
    public class LocalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 140, GroupName = GroupNames.StatUnitInfo)]
        public int? LegalUnitId { get; set; }

        [Display(Order = 141, GroupName = GroupNames.StatUnitInfo)]
        public DateTime LegalUnitIdDate { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public virtual LegalUnit LegalUnit { get; set; }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public override int? InstSectorCodeId
        {
            get => null;
            set { }
        }

        [NotMappedFor(ActionsEnum.Create | ActionsEnum.Edit | ActionsEnum.View)]
        public override int? LegalFormId
        {
            get => null;
            set { }
        }

        [SearchComponent]
        [Display(Order = 142, GroupName = GroupNames.StatUnitInfo)]
        public override int? ParentOrgLink { get; set; }
    }
}
