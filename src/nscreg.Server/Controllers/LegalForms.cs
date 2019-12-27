using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services.CodeLookup;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Legal Controller
    /// </summary>
    [Route("api/[controller]")]
    public class LegalFormsController:Controller
    {
        private readonly CodeLookupService<LegalForm> _service;

        public LegalFormsController(NSCRegDbContext dbContext)
        {
            _service = new CodeLookupService<LegalForm>(dbContext);
        }

        /// <summary>
        /// Legal ownership method
        /// </summary>
        /// <param name="wildcard">Request Template</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));

        /// <summary>
        /// Method of obtaining legal form of ownership
        /// </summary>
        /// <param name="id">Id of legal form of ownership</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id) => Ok(await _service.GetById(id));
    }
}
