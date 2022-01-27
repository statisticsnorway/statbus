using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;
using nscreg.Data.Repositories;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Services.CodeLookup
{
    /// <summary>
    /// Service
    /// </summary>
    public class CodeLookupService<T> where T : CodeLookupBase
    {
        private readonly CodeLookupRepository<T> _repository;
        private readonly CodeLookupStrategy<T> _filterStrategy;

        public CodeLookupService(DbContext context)
        {
            _repository = new CodeLookupRepository<T>(context);
            _filterStrategy = CodeLookupStrategy<T>.Create();
        }

        public virtual async Task<List<CodeLookupVm>> List(bool showDeleted = false,
            Expression<Func<T, bool>> predicate = null)
        {
            var query = _repository.List(showDeleted);
            if (predicate != null)
            {
                query = Queryable.Where(query, predicate);
            }
            return await ToViewModel(query);
        }

        public virtual async Task<List<CodeLookupVm>> Search(string wildcard, int limit = 5, bool showDeleted = false, string userId = null)
        {
            var query = _filterStrategy.Filter(_repository.List(showDeleted), wildcard, userId);
            return await ToViewModel(Queryable.OrderBy(query, v => v.Code)
                .Take(limit));
        }

        public virtual async Task<CodeLookupVm> GetById(int id, bool showDeleted = false)
        {
            var modelId = await Queryable.Select(Queryable.Where(_repository.List(showDeleted), v => v.Id == id), v => new CodeLookupVm
                {
                    Id = v.Id,
                    Code = v.Code,
                    Name = v.Name,
                    NameLanguage1 = v.NameLanguage1,
                    NameLanguage2 = v.NameLanguage2
                })
            .FirstOrDefaultAsync();
            return modelId;
        }


        protected virtual async Task<List<CodeLookupVm>> ToViewModel(IQueryable<T> query) => await Queryable.Select(query, v =>
                new CodeLookupVm
                {
                    Id = v.Id,
                    Code = v.Code,
                    Name = v.Name,
                    NameLanguage1 = v.NameLanguage1,
                    NameLanguage2 = v.NameLanguage2
                })
            .ToListAsync();
    }
}
