using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Entities;

namespace nscreg.Data.Repositories
{
    /// <summary>
    /// Code Reference Repository Class
    /// </summary>
    /// <typeparam name="TEntity"></typeparam>
    public class CodeLookupRepository<TEntity> : LookupRepository<TEntity> where TEntity : CodeLookupBase
    {
        public CodeLookupRepository(DbContext context) : base(context)
        {
        }

        /// <summary>
        /// Code Search Method
        /// </summary>
        /// <param name="code">parameter receiving code</param>
        /// <param name="showDeleted">distance flag parameter</param>
        /// <returns></returns>
        public virtual async Task<TEntity> Find(string code, bool showDeleted = false)
            => await List(showDeleted).FirstAsync(v => v.Code == code);

        /// <summary>
        /// Code List Retrieval Method
        /// </summary>
        /// <param name="code">parameter receiving code</param>
        /// <param name="showDeleted">distance flag parameter</param>
        /// <returns></returns>
        public virtual async Task<TEntity> Get(string code, bool showDeleted = false)
            => await List(showDeleted).SingleAsync(v => v.Code == code);
    }
}
