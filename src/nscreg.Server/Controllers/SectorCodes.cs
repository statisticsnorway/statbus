using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services.CodeLookup;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Sector Code Controller
    /// </summary>
    [Route("api/[controller]")]
    public class SectorCodesController : Controller
    {
        private readonly CodeLookupService<SectorCode> _service;

        public SectorCodesController(NSCRegDbContext dbContext)
        {
            _service = new CodeLookupService<SectorCode>(dbContext);
        }

        /// <summary>
        /// Sector Code Search Method
        /// </summary>
        /// <param name="wildcard">wildcard</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) => Ok(await _service.Search(wildcard));

        /// <summary>
        /// Sector Code Retrieval Method
        /// </summary>
        /// <param name="id">Sector Id</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id) => Ok(await _service.GetById(id));
    }
}
