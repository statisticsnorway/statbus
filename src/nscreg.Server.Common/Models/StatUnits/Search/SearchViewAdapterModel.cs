using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class SearchViewAdapterModel : StatUnitSearchView
    {
        public SearchViewAdapterModel(StatUnitSearchView view, IEnumerable<string> personNames, IEnumerable<string> mainActivities, string region)
        {
            Mapper.Map(view, this);
            Persons = new PersonAdapterModel(string.Join(", ", personNames));
            Activities = new ActivityAdapterModel(string.Join(", ", mainActivities));
            Address.RegionFullPath = region;
        }

        public AddressAdapterModel Address { get; set; }
        public PersonAdapterModel Persons { get; set; }
        public ActivityAdapterModel Activities { get; set; }

    }
}
