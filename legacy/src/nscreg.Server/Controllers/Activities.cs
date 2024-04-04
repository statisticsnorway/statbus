using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services.CodeLookup;
using nscreg.Server.Core;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Activity controller
    /// </summary>
    [Route("api/[controller]")]
    public class ActivitiesController : Controller
    {
        private readonly CodeLookupService<ActivityCategory> _service;

        public ActivitiesController(NSCRegDbContext db)
        {
            _service = new CodeLookupService<ActivityCategory>(db);
        }
        /// <summary>
        /// Activity Search Method
        /// </summary>
        /// <param name="wildcard">Search pattern</param>
        /// <returns></returns>
        [HttpGet]
        [Route("search")]
        public async Task<IActionResult> Search(string wildcard) =>
            Ok(await _service.Search(wildcard, userId: User.IsInRole(DefaultRoleNames.Administrator) ? null : User.GetUserId()));
    }
}
