using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/statunits/deleted")]
    public class StatUnitsDeletedController : Controller
    {
        private readonly StatUnitService _statUnitService;

        public StatUnitsDeletedController(NSCRegDbContext context)
        {
            _statUnitService = new StatUnitService(context);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public async Task<IActionResult> GetDeleted(SearchQueryM data)
            => Ok(await _statUnitService.Search(data, User.GetUserId(), true));

        [HttpDelete]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public IActionResult Restore(StatUnitTypes type, int regId)
        {
            _statUnitService.DeleteUndelete(type, regId, false, User.GetUserId());
            return NoContent();
        }
    }
}
