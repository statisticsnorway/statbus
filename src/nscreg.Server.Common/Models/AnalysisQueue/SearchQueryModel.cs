using System;

namespace nscreg.Server.Common.Models.AnalysisQueue
{
    public class SearchQueryModel : PaginatedQueryM
    {
        public DateTime? DateFrom { get; set; }
        public DateTime? DateTo { get; set; }
    }
}
