using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/statunits/deleted")]
    public class DeletedStatUnitsController : Controller
    {
        private readonly StatUnitService _statUnitService;

        public DeletedStatUnitsController(NSCRegDbContext context)
        {
            _statUnitService = new StatUnitService(context);
        }

        [HttpGet]
        public IActionResult GetDeleted(SearchDeletedQueryM data) => Ok(_statUnitService.SearchDeleted(data));

        [HttpDelete]
        public IActionResult Restore(StatUnitTypes type, int regId)
        {
            _statUnitService.DeleteUndelete(type, regId, false);
            return NoContent();
        }
    }
}
