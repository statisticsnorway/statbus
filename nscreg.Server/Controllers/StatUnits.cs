using System.Globalization;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using System.Linq;
using nscreg.Server.Services;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Data.Entities;
using nscreg.Server.Models.Users;
using nscreg.Utilities;

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
        public IActionResult GetEntityById(int unitType, int id)
        {
            try
            {
                var unit = unitServices.GetUnitById(unitType, id);

                return Ok(unit);
            }
            catch (MyNotFoundException ex)
            {
                return (IActionResult)NotFound();
            }
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(int unitType, int id)
        {
            try
            {
                unitServices.DeleteUndelete(unitType, id, true);
                return (IActionResult)NoContent();
            }
            catch (MyNotFoundException ex)
            {
                return BadRequest(new { message = ex });
            }
        }

        [HttpPut("{id}/[action]")]
        public IActionResult UnDelete(int unitType, int id)
        {
            try
            {
                unitServices.DeleteUndelete(unitType, id, false);
                return (IActionResult)NoContent();
            }
            catch (MyNotFoundException ex)
            {
                return BadRequest(new { message = ex });
            }
        }

        [HttpPost("LegalUnit")]
        public IActionResult CreateLegalUnit([FromBody] LegalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                unitServices.CreateLegalUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new { e.Message });
            }
        }
        [HttpPost("LocalUnit")]
        public IActionResult CreateLocalUnit([FromBody] LocalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                unitServices.CreateLocalUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new { e.Message });
            }
        }

        [HttpPost("EnterpriseUnit")]
        public IActionResult CreateEnterpriseUnit([FromBody] EnterpriseUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                unitServices.CreateEnterpriseUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new { e.Message });
            }
        }

        [HttpPost("EnterpriseGroup")]
        public IActionResult CreateEnterpriseGroup([FromBody] EnterpriseGroupSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                unitServices.CreateEnterpriseGroupUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new { e.Message });
            }
        }

    }
}
