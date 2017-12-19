using System;
using System.Collections.Generic;
using System.Text;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class LogsQueryModel:PaginatedQueryM
    {
        public int QueueId { get; set; }
    }
}
