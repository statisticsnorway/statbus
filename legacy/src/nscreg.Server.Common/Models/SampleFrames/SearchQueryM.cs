using System;
using System.Collections.Generic;
using System.Text;

namespace nscreg.Server.Common.Models.SampleFrames
{
    public class SearchQueryM
    {
        public string Wildcard { get; set; }
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;
    }
}
