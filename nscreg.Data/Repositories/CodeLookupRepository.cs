using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;

namespace nscreg.Data.Repositories
{
    public class CodeLookupRepository<TEntity> : LookupRepository<TEntity> where TEntity: CodeLookupBase
    {
        public CodeLookupRepository(DbContext context) : base(context)
        {
        }

        public virtual async Task<TEntity> Find(string code, bool showDeleted = false)
        {
            return await List(showDeleted).FirstAsync(v => v.Code == code);
        }

        public virtual async Task<TEntity> Get(string code, bool showDeleted = false)
        {
            return await List(showDeleted).SingleAsync(v => v.Code == code);
        }
    }
}
