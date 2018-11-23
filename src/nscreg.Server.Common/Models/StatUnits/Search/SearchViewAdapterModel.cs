using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class SearchViewAdapterModel : StatUnitSearchView
    {
        public SearchViewAdapterModel(StatUnitSearchView view, IEnumerable<string> personNames, IEnumerable<CodeLookupVm> mainActivities, RegionLookupVm region)
        {
            Mapper.Map(view, this);
            Persons = new PersonAdapterModel(string.Join(", ", personNames));
            Activities = new ActivityAdapterModel(string.Join(", ", mainActivities.Select(x=>x.Name)), string.Join(", ", mainActivities.Select(x=>x.NameLanguage1)), string.Join(", ", mainActivities.Select(x=>x.NameLanguage2)));
            Address.RegionFullPath = region.FullPath;
            Address.RegionFullPathLanguage1 = region.FullPathLanguage1;
            Address.RegionFullPathLanguage2 = region.FullPathLanguage2;
        }

        public AddressAdapterModel Address { get; set; }
        public PersonAdapterModel Persons { get; set; }
        public ActivityAdapterModel Activities { get; set; }

    }
}
