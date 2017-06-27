using FluentValidation;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.Links
{
    public class FetchOrgLinkM
    {
        public UnitSubmitM Source { get; set; }
        public string Name { get; set; }
        public StatUnitTypes? Type { get; set; }
    }
}