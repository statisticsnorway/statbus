using System;
using System.Collections.Generic;
using System.Text;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class AnalisysQueueCreateModel
    {
        public DateTimeOffset? DateFrom { get; set; }
        public DateTimeOffset? DateTo { get; set; }
        public string Comment { get; set; }
    }
}
