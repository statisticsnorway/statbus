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
    ///  Class entity history legal unity
    /// </summary>
    public class LegalUnitHistory : StatisticalUnitHistory
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;

        public int? EnterpriseUnitRegId { get; set; }

        public DateTimeOffset? EntRegIdDate { get; set; }

        public bool Market { get; set; }
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

        public string HistoryLocalUnitIds { get; set; }

    }
}
