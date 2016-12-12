using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Data.Constants;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatUnitsController : Controller
    {
        private readonly NSCRegDbContext _context;
        private readonly StatUnitService _statUnitService;

        public StatUnitsController(NSCRegDbContext context)
        {
            _context = context;
            _statUnitService = new StatUnitService(context);
        }

        [HttpGet("{id}")]
        public IActionResult GetEntityById(StatUnitTypes unitType, int id)
        {
            var unit = _statUnitService.GetUnitById(unitType, id);
            return Ok(unit);
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(StatUnitTypes unitType, int id)
        {
            _statUnitService.DeleteUndelete(unitType, id, true);
            return NoContent();
        }

        [HttpPut("{id}/[action]")]
        public IActionResult UnDelete(StatUnitTypes unitType, int id)
        {
            _statUnitService.DeleteUndelete(unitType, id, false);
            return NoContent();
        }

        [HttpPost("LegalUnit")]
        public IActionResult CreateLegalUnit([FromBody] LegalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _statUnitService.CreateLegalUnit(data);
            return Ok();
        }

        [HttpPost("LocalUnit")]
        public IActionResult CreateLocalUnit([FromBody] LocalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _statUnitService.CreateLocalUnit(data);
            return Ok();
        }

        [HttpPost("EnterpriseUnit")]
        public IActionResult CreateEnterpriseUnit([FromBody] EnterpriseUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _statUnitService.CreateEnterpriseUnit(data);
            return Ok();
        }

        [HttpPost("EnterpriseGroup")]
        public IActionResult CreateEnterpriseGroup([FromBody] EnterpriseGroupSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _statUnitService.CreateEnterpriseGroupUnit(data);
            return Ok();
        }
    }
}
