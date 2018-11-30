using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Regions
{
    /// <summary>
    /// Модель узла региона
    /// </summary>
    public class RegionNode
        {
            public int Id { get; set; }
            public string Name { get; set; }
            public string NameLanguage1 { get; set; }
            public string NameLanguage2 { get; set; }
            public string Code { get; set; }
            public IEnumerable<RegionNode> RegionNodes { get; set; }
        }
}
