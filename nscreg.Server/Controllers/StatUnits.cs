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
        private readonly StatUnitService _unitServices;

        public StatUnitsController(NSCRegDbContext context)
        {
            _context = context;
            _unitServices = new StatUnitService(context);
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
                var unit = _unitServices.GetUnitById(unitType, id);

                return Ok(unit);
            }
            catch (MyNotFoundException)
            {
                return NotFound();
            }
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(int unitType, int id)
        {
            try
            {
                _unitServices.DeleteUndelete(unitType, id, true);
                return NoContent();
            }
            catch (MyNotFoundException ex)
            {
                return BadRequest(new {message = ex});
            }
        }

        [HttpPut("{id}/[action]")]
        public IActionResult UnDelete(int unitType, int id)
        {
            try
            {
                _unitServices.DeleteUndelete(unitType, id, false);
                return NoContent();
            }
            catch (MyNotFoundException ex)
            {
                return BadRequest(new {message = ex});
            }
        }

        [HttpPost("LegalUnit")]
        public IActionResult CreateLegalUnit([FromBody] LegalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                _unitServices.CreateLegalUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new {e.Message});
            }
        }

        [HttpPost("LocalUnit")]
        public IActionResult CreateLocalUnit([FromBody] LocalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                _unitServices.CreateLocalUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new {e.Message});
            }
        }

        [HttpPost("EnterpriseUnit")]
        public IActionResult CreateEnterpriseUnit([FromBody] EnterpriseUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                _unitServices.CreateEnterpriseUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new {e.Message});
            }
        }

        [HttpPost("EnterpriseGroup")]
        public IActionResult CreateEnterpriseGroup([FromBody] EnterpriseGroupSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            try
            {
                _unitServices.CreateEnterpriseGroupUnit(data);
                return Ok();
            }
            catch (StatisticalUnitCreateException e)
            {
                return BadRequest(new {e.Message});
            }
        }

    }
}
