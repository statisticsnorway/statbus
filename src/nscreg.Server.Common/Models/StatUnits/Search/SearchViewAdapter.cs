using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class SearchViewAdapter : StatUnitSearchView
    {
        private SearchViewAdapter(StatUnitSearchView view)
        {
            Address = new AddressAdapter(view);
            Mapper.Map(view, this);
        }

        public AddressAdapter Address { get; }
        public PersonModel Persons { get; private set; }

        public static SearchViewAdapter Create(StatUnitSearchView view, IEnumerable<Person> persons)
        {
            return new SearchViewAdapter(view)
            {
                Persons = new PersonModel
                {
                    ContactPerson = string.Join(",", persons.Select(x => x.GivenName))
                }
            };
        }
    }
}
