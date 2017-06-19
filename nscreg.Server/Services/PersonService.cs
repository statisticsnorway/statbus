using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Models.StatUnits;

namespace nscreg.Server.Services
{
    public class PersonService
    {
        private readonly NSCRegDbContext _context;

        public PersonService(NSCRegDbContext context)
        {
            _context = context;
        }

        public virtual async Task<List<PersonM>> Search(string wildcard, int limit = 5)
        {
            wildcard = wildcard.ToLower();
            return await ToViewModel(_context.Persons.Where(v =>
                    v.GivenName.ToLower().Contains(wildcard) ||
                    v.Surname.ToLower().Contains(wildcard)
                )
                .OrderBy(v => v.GivenName).Take(limit));
        }

        protected virtual async Task<List<PersonM>> ToViewModel(IQueryable<Person> query)
        {
            return await query.Select(v => new PersonM()
            {
                Id = v.Id,
                Address = v.Address,
                Role = v.Role,
                Surname = v.Surname,
                GivenName = v.GivenName,
                BirthDate = v.BirthDate,
                CountryId = v.CountryId,
                PersonalId = v.PersonalId,
                PhoneNumber = v.PhoneNumber,
                PhoneNumber1 = v.PhoneNumber1,
                Sex = v.Sex
            }).ToListAsync();
        }
    }
}
