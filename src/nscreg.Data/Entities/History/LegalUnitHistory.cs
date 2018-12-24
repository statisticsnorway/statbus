using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Класс сущность история правовой единцы
    /// </summary>
    public class LegalUnitHistory : StatisticalUnitHistory
    {
        public override StatUnitTypes UnitType => StatUnitTypes.LegalUnit;

        public int? EnterpriseUnitRegId { get; set; }

        public DateTime? EntRegIdDate { get; set; }

        public bool Market { get; set; }

        public string TotalCapital { get; set; }

        public string MunCapitalShare { get; set; }

        public string StateCapitalShare { get; set; }

        public string PrivCapitalShare { get; set; }

        public string ForeignCapitalShare { get; set; }

        public string ForeignCapitalCurrency { get; set; }

        public virtual EnterpriseUnitHistory EnterpriseUnit { get; set; }

        public string HistoryLocalUnitIds { get; set; }

    }
}
