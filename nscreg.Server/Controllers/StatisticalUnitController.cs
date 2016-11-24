using System.Globalization;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Linq;
using nscreg.Server.Services;
using nscreg.Utilities;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatisticalUnitController : Controller
    {
        private readonly NSCRegDbContext _context;
        private StatisticalUnitServices unitServices = new StatisticalUnitServices();

        public StatisticalUnitController(NSCRegDbContext context)
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
    }
}
