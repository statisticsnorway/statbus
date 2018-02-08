using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class SearchViewAdapterModel : StatUnitSearchView
    {
        public SearchViewAdapterModel(StatUnitSearchView view, IEnumerable<string> personNames, string mainActivity)
        {
            Mapper.Map(view, this);
            Persons = new PersonAdapterModel(string.Join(",", personNames));
            Activities = new ActivityAdapterModel(mainActivity);
        }

        public AddressAdapterModel Address { get; set; }
        public PersonAdapterModel Persons { get; set; }
        public ActivityAdapterModel Activities { get; set; }

    }
}
