using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Data.Enums;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatUnitsController : Controller
    {
        private readonly NSCRegDbContext _context;
        private StatisticalUnitServices unitServices;

        public StatUnitsController(NSCRegDbContext context)
        {
            _context = context;
            unitServices = new StatisticalUnitServices(context);
        }

        [HttpGet]
        public IActionResult GetAllStatisticalUnits([FromQuery] int page = 0, [FromQuery] int pageSize = 20,
    [FromQuery] bool showAll = false)
    => Ok(StatisticalUnitsListVm.Create(_context, page, pageSize, showAll));

        [HttpGet("{id}")]
        public IActionResult GetEntityById(StatisticalUnitTypes unitType, int id)
        {
            var unit = unitServices.GetUnitById(unitType, id);
            return Ok(unit);
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(StatisticalUnitTypes unitType, int id)
        {
            unitServices.DeleteUndelete(unitType, id, true);
            return NoContent();
        }

        [HttpPut("{id}/[action]")]
        public IActionResult UnDelete(StatisticalUnitTypes unitType, int id)
        {
            unitServices.DeleteUndelete(unitType, id, false);
            return NoContent();
        }
    }
}
