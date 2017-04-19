using nscreg.Utilities.Enums;
using System;

namespace nscreg.Server.Models.DataSources
{
    public class SearchQueryM
    {
        public string Wildcard { get; set; }
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;
        public string SortBy { get; set; }
        public OrderRule OrderByValue { get; private set; } = OrderRule.Asc;
        public string OrderBy
        {
            set
            {
                OrderRule parsed;
                if (Enum.TryParse(value, out parsed))
                    OrderByValue = parsed;
            }
        }
    }
}
