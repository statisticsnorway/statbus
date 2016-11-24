using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Linq;
using nscreg.Server.Services;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Data.Entities;
using nscreg.Utilities;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatisticalUnitController : Controller
    {
        private readonly NSCRegDbContext _context;

        public StatisticalUnitController(NSCRegDbContext context)
        {
            _context = context;
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(int id)
        {
            var resp = StatisticalUnitServices.Delete(_context, id);
            if (resp.Equals("OK"))
            {
                return (IActionResult)NoContent();
            }
            return BadRequest(new { message = "Error while deleting Statistical Unit" });
        }

        [HttpPost]
        public IActionResult Create([FromBody] StatisticalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                new StatisticalUnitServices().Create(_context, data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new {e.Message});
            }
        }

    }
}
