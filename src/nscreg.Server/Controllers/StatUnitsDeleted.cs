using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    [Route("api/statunits/deleted")]
    public class StatUnitsDeletedController : Controller
    {
        private readonly DeleteService _deleteService;
        private readonly SearchService _searchService;

        public StatUnitsDeletedController(NSCRegDbContext context)
        {
            _deleteService = new DeleteService(context);
            _searchService = new SearchService(context);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public async Task<IActionResult> GetDeleted(SearchQueryM data)
            => Ok(await _searchService.Search(data, User.GetUserId(), true));

        [HttpDelete]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public IActionResult Restore(StatUnitTypes type, int regId)
        {
            _deleteService.DeleteUndelete(type, regId, false, User.GetUserId());
            return NoContent();
        }
    }
}
