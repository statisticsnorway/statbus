using System;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class SearchQueryModel : PaginatedQueryM
    {
        public DateTimeOffset? DateFrom { get; set; }
        public DateTimeOffset? DateTo { get; set; }
    }
}
