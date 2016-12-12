using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
using nscreg.Server.Models.StatisticalUnit;
using nscreg.Data.Constants;
using nscreg.Server.Models.StatisticalUnit.Edit;
using nscreg.Server.Models.StatisticalUnit.Submit;

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
        public IActionResult GetEntityById(StatUnitTypes unitType, int id)
        {
            var unit = _unitServices.GetUnitById(unitType, id);
            return Ok(unit);
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(StatUnitTypes unitType, int id)
        {
            _unitServices.DeleteUndelete(unitType, id, true);
            return NoContent();
        }

        [HttpPut("{id}/[action]")]
        public IActionResult UnDelete(StatUnitTypes unitType, int id)
        {
            _unitServices.DeleteUndelete(unitType, id, false);
            return NoContent();
        }

        [HttpPost("LegalUnit")]
        public IActionResult CreateLegalUnit([FromBody] LegalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.CreateLegalUnit(data);
            return Ok();
        }

        [HttpPost("LocalUnit")]
        public IActionResult CreateLocalUnit([FromBody] LocalUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.CreateLocalUnit(data);
            return Ok();
        }

        [HttpPost("EnterpriseUnit")]
        public IActionResult CreateEnterpriseUnit([FromBody] EnterpriseUnitSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.CreateEnterpriseUnit(data);
            return Ok();
        }

        [HttpPost("EnterpriseGroup")]
        public IActionResult CreateEnterpriseGroup([FromBody] EnterpriseGroupSubmitM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.CreateEnterpriseGroupUnit(data);
            return Ok();
        }

        [HttpPut("LegalUnit")]
        public IActionResult EditLegalUnit([FromBody] LegalUnitEditM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.EditLegalUnit(data);
            return NoContent();
        }

        [HttpPut("LocalUnit")]
        public IActionResult EditLocalUnit([FromBody] LocalUnitEditM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.EditLocalUnit(data);
            return NoContent();
        }
        [HttpPut("EnterpriseUnit")]
        public IActionResult EditEnterpriseUnit([FromBody] EnterpriseUnitEditM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.EditEnterpiseUnit(data);
            return NoContent();
        }
        [HttpPut("EnterpriseGroup")]
        public IActionResult EditEnterpriseGroup([FromBody] EnterpriseGroupEditM data)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            _unitServices.EditEnterpiseGroup(data);
            return NoContent();
        }
    }
}
