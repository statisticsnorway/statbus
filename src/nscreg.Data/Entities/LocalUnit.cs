using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity local unit
    /// </summary>
    public class LocalUnit : StatisticalUnit
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LocalUnit;

        [Reference(LookupEnum.LegalUnitLookup)]
        [Display(Order = 200, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("LegalUnitIdTooltip")]
        public int? LegalUnitId { get; set; }

        [Display(Order = 201, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("LegalUnitIdDateTooltip")]
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
        [Display(Order = 202, GroupName = GroupNames.LinkInfo)]
        [PopupLocalizedKey("ParentOrgLinkTooltip")]
        public override int? ParentOrgLink { get; set; }
    }
}
