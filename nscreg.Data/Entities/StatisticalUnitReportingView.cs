using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;

namespace nscreg.Data.Entities
{
    public class StatisticalUnitReportingView
    {
        public int Id { get; set; }
        public int StatId { get; set; }
        public StatisticalUnit StatisticalUnit { get; set; }

        public int RepViewId { get; set; }
        public ReportingView ReportingView { get; set; }
    }
}
