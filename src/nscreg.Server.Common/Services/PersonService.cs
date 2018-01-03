using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис персон
    /// </summary>
    public class PersonService
    {
        private readonly NSCRegDbContext _context;

        public PersonService(NSCRegDbContext context)
        {
            _context = context;
        }

        /// <summary>
        ///  Метод поиска персоны
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <param name="limit">Ограничение</param>
        /// <returns></returns>
        public async Task<List<PersonM>> Search(string wildcard, int limit = 5)
        {
            var loweredwc = wildcard.ToLower();
            return await ToViewModel(_context.Persons.Where(v =>
                    v.GivenName.ToLower().Contains(loweredwc) ||
                    v.Surname.ToLower().Contains(loweredwc))
                .GroupBy(g => new {g.GivenName,
                                   g.MiddleName,
                                   g.Surname,
                                   g.Address,
                                   g.BirthDate,
                                   g.CountryId,
                                   g.PersonalId,
                                   g.PhoneNumber,
                                   g.PhoneNumber1,
                                   g.Role,
                                   g.Sex})
                .Select(s => s.First())
                .OrderBy(v => v.GivenName).Take(limit));
        }

        /// <summary>
        /// Метод преобразования данных ко вью модели
        /// </summary>
        /// <param name="query">Запрос</param>
        /// <returns></returns>
        private static async Task<List<PersonM>> ToViewModel(IQueryable<Person> query)
            => await query.Select(v => new PersonM
            {
                Id = v.Id,
                Address = v.Address,
                Role = v.Role,
                Surname = v.Surname,
                MiddleName = v.MiddleName,
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
