using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;
using nscreg.Data.Repositories;
using nscreg.Server.Common.Models.Lookup;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис
    /// </summary>
    public class CodeLookupService<T> where T: CodeLookupBase
    {
        private readonly CodeLookupRepository<T> _repository;

        public CodeLookupService(DbContext context)
        {
            _repository = new CodeLookupRepository<T>(context);
        }

        public virtual async Task<List<CodeLookupVm>> List(bool showDeleted = false, Expression<Func<T, bool>> predicate = null)
        {
            var query = _repository.List(showDeleted);
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            return await ToViewModel(query);
        }

        public virtual async Task<List<CodeLookupVm>> Search(string wildcard, int limit = 5, bool showDeleted = false)
        {
            var loweredwc = wildcard.ToLower();
            return await ToViewModel(_repository.List(showDeleted)
                .Where(v => v.Code.StartsWith(loweredwc) || v.Name.ToLower().Contains(loweredwc))
                .OrderBy(v => v.Code)
                .Take(limit));
        }

        public virtual async Task<CodeLookupVm> GetById(int id, bool showDeleted = false)
            => await _repository.List(showDeleted).Where(v => v.Id == id).Select(v => new CodeLookupVm
            {
                Id = v.Id,
                Code = v.Code,
                Name = v.Name,
            })
            .FirstOrDefaultAsync();

        protected virtual async Task<List<CodeLookupVm>> ToViewModel(IQueryable<T> query) => await query.Select(v => new CodeLookupVm
        {
            Id = v.Id,
            Code = v.Code,
            Name = v.Name,
        })
            .ToListAsync();
    }
}
