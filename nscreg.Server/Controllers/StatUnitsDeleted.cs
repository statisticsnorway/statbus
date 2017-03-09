using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Extension;
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
        public IActionResult GetDeleted(SearchQueryM data)
            => Ok(_statUnitService.Search(data, User.GetUserId(), true));

        [HttpDelete]
        public IActionResult Restore(StatUnitTypes type, int regId)
        {
            _statUnitService.DeleteUndelete(type, regId, false);
            return NoContent();
        }
    }
}
