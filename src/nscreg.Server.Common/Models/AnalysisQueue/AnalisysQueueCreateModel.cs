using System;
using System.Collections.Generic;
using System.Text;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class AnalisysQueueCreateModel
    {
        public DateTime? DateFrom { get; set; }
        public DateTime? DateTo { get; set; }
        public string Comment { get; set; }
    }
}
