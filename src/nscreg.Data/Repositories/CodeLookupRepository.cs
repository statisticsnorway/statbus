using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;

namespace nscreg.Data.Repositories
{
    /// <summary>
    /// Класс репозиторий справочника кода
    /// </summary>
    /// <typeparam name="TEntity"></typeparam>
    public class CodeLookupRepository<TEntity> : LookupRepository<TEntity> where TEntity : CodeLookupBase
    {
        public CodeLookupRepository(DbContext context) : base(context)
        {
        }

        /// <summary>
        /// Метод поиска кода
        /// </summary>
        /// <param name="code">параметр принимающий код</param>
        /// <param name="showDeleted">параметр флаг удалённости</param>
        /// <returns></returns>
        public virtual async Task<TEntity> Find(string code, bool showDeleted = false)
            => await List(showDeleted).FirstAsync(v => v.Code == code);

        /// <summary>
        /// Метод получения списка кодов
        /// </summary>
        /// <param name="code">параметр принимающий код</param>
        /// <param name="showDeleted">параметр флаг удалённости</param>
        /// <returns></returns>
        public virtual async Task<TEntity> Get(string code, bool showDeleted = false)
            => await List(showDeleted).SingleAsync(v => v.Code == code);
    }
}
