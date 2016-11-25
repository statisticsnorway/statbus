using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Utilities;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatUnitsController : Controller
    {
        private readonly NSCRegDbContext _context;
        private StatisticalUnitServices unitServices = new StatisticalUnitServices();

        public StatUnitsController(NSCRegDbContext context)
        {
            _context = context;
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(int unitType, int id)
        {
            try
            {
                unitServices.Delete(_context, unitType, id);
                return (IActionResult)NoContent();
            }
            catch (UnitNotFoundException ex)
            {
                return BadRequest(new { message = ex });
            }
        }

        [HttpPost]
        public IActionResult Create([FromBody] StatisticalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                unitServices.Create(_context, data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new {e.Message});
            }
        }

    }
}
