using System;
using System.Collections.Generic;
using System.Text;
using nscreg.Server.Common.Models.Addresses;

namespace nscreg.Server.Common.Models
{
    public class PaginatedResultModelBase<T>
    {
        public IList<T> Items { get; set; }

        public int TotalCount { get; set; }

        public int TotalPages { get; set; }

        public int CurrentPage { get; set; }

        public int PageSize { get; set; }
    }
}
