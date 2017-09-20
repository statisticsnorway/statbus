using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;

namespace nscreg.Data.Repositories
{
    /// <summary>
    /// Класс репозиторий справочников
    /// </summary>
    /// <typeparam name="TEntity"></typeparam>
    public class LookupRepository<TEntity> where TEntity : LookupBase
    {
        private readonly IQueryable<TEntity> _query;

        public LookupRepository(DbContext context)
        {
            _query = context.Set<TEntity>();
        }

        /// <summary>
        /// Find метод находит список сущностей по id
        /// </summary>
        /// <param name="id">id сущности</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public virtual async Task<TEntity> Find(int id, bool showDeleted = false)
            => await List(showDeleted).FirstAsync(v => v.Id == id);

        /// <summary>
        /// Метод получения списка сущностей
        /// </summary>
        /// <param name="id">id сущности</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public virtual async Task<TEntity> Get(int id, bool showDeleted = false)
            => await List(showDeleted).SingleAsync(v => v.Id == id);

        /// <summary>
        /// Метод получения списка
        /// </summary>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
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
