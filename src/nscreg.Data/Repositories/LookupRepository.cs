using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;

namespace nscreg.Data.Repositories
{
    public class LookupRepository<TEntity> where TEntity : LookupBase
    {
        private readonly IQueryable<TEntity> _query;

        public LookupRepository(DbContext context)
        {
            _query = context.Set<TEntity>();
        }

        public virtual async Task<TEntity> Find(int id, bool showDeleted = false)
            => await List(showDeleted).FirstAsync(v => v.Id == id);

        public virtual async Task<TEntity> Get(int id, bool showDeleted = false)
            => await List(showDeleted).SingleAsync(v => v.Id == id);

        public virtual IQueryable<TEntity> List(bool showDeleted = false)
        {
            var list = _query;
            if (!showDeleted)
            {
                list = list.Where(v => v.IsDeleted == false);
            }
            return list;
        }
    }
}
