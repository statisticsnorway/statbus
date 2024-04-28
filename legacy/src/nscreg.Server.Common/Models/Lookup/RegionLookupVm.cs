using System;
using System.Collections.Generic;
using System.Text;

namespace nscreg.Server.Common.Models.Lookup
{
    public class RegionLookupVm
    {
        public int Id { get; set; }
        public string FullPath { get; set; }
        public string FullPathLanguage1 { get; set; }
        public string FullPathLanguage2 { get; set; }
    }
}
