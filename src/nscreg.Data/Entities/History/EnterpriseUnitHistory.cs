using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace nscreg.Data.Entities.History
{
    /// <summary>
    ///  Класс сущность история предприятия
    /// </summary>
    public class EnterpriseUnitHistory : StatisticalUnitHistory
    {
        public override StatUnitTypes UnitType => StatUnitTypes.EnterpriseUnit;

        public int? EntGroupId { get; set; }
    
        public DateTime EntGroupIdDate { get; set; }

        public string EntGroupRole { get; set; }

        public override int? ParentOrgLink { get; set; }

        public bool Commercial { get; set; }

        public string TotalCapital { get; set; }

        public string MunCapitalShare { get; set; }

        public string StateCapitalShare { get; set; }

        public string PrivCapitalShare { get; set; }

        public string ForeignCapitalShare { get; set; }

        public string ForeignCapitalCurrency { get; set; }

        public virtual EnterpriseGroupHistory EnterpriseGroup { get; set; }

        public string HistoryLegalUnitIds { get; set; }

        public override int? LegalFormId
        {
            get => null;
            set { }
        }

    }
}
