using System;
using System.Collections.Generic;
using System.Text;
using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class LogItemModel
    {
        public int Id { get; set; }
        public int UnitId { get; set; }
        public string UnitName { get; set; }
        public string UnitType { get; set; }
        public string[] SummaryMessages { get; set; }
    }
}
