using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Linq;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatisticalUnitController : Controller
    {
        private readonly NSCRegDbContext _context;

        [HttpDelete("{id}")]
        public IActionResult Delete(int id)
        {
            var resp = StatisticalUnitServices.Delete(_context, id);
            if (resp.Equals("OK"))
            {
                return (IActionResult) NoContent();
            }
            return BadRequest(new { message = "Error while deleting Statistical Unit" });
        }
    }
}
