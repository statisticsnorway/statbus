using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Class entity history of the enterprise
    /// </summary>
    public class EnterpriseUnitHistory : StatisticalUnitHistory
    {
        public override StatUnitTypes UnitType => StatUnitTypes.EnterpriseUnit;

        public int? EntGroupId { get; set; }

        public DateTimeOffset EntGroupIdDate { get; set; }

        public string EntGroupRole { get; set; }

        public override int? ParentOrgLink { get; set; }

        public bool Commercial { get; set; }

        [Column(nameof(TotalCapital))]
        public string TotalCapital { get; set; }

        [Column(nameof(MunCapitalShare))]
        public string MunCapitalShare { get; set; }

        [Column(nameof(StateCapitalShare))]
        public string StateCapitalShare { get; set; }

        [Column(nameof(PrivCapitalShare))]
        public string PrivCapitalShare { get; set; }

        [Column(nameof(ForeignCapitalShare))]
        public string ForeignCapitalShare { get; set; }

        [Column(nameof(ForeignCapitalCurrency))]
        public string ForeignCapitalCurrency { get; set; }

        public string HistoryLegalUnitIds { get; set; }

        public override int? LegalFormId
        {
            get => null;
            set { }
        }

    }
}
