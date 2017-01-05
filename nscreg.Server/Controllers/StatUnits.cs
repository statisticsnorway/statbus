using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Data.Constants;
using System;
using nscreg.Data.Entities;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class StatUnitsController : Controller
    {
        private readonly StatUnitService _statUnitService;

        public StatUnitsController(NSCRegDbContext context)
        {
            _statUnitService = new StatUnitService(context);
        }

        [HttpGet]
        public IActionResult Search([FromQuery] SearchQueryM query)
            => Ok(_statUnitService.Search(query,
                User.FindFirst(CustomClaimTypes.DataAccessAttributes)?.Value.Split(',')
                ?? Array.Empty<string>()));

        [HttpGet("{id}")]
        public IActionResult GetEntityById(int id)
        {
            var unit = _statUnitService.GetUnitById(id, User.FindFirst(CustomClaimTypes.DataAccessAttributes)?.Value.Split(','));
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
        public IActionResult CreateLegalUnit([FromBody] LegalUnitCreateM data)
        {
            _statUnitService.CreateLegalUnit(data);
            return Ok();
        }

        [HttpPost("LocalUnit")]
        public IActionResult CreateLocalUnit([FromBody] LocalUnitCreateM data)
        {
            _statUnitService.CreateLocalUnit(data);
            return Ok();
        }

        [HttpPost("EnterpriseUnit")]
        public IActionResult CreateEnterpriseUnit([FromBody] EnterpriseUnitCreateM data)
        {
            _statUnitService.CreateEnterpriseUnit(data);
            return Ok();
        }

        [HttpPost("EnterpriseGroup")]
        public IActionResult CreateEnterpriseGroup([FromBody] EnterpriseGroupCreateM data)
        {
            _statUnitService.CreateEnterpriseGroupUnit(data);
            return Ok();
        }

        [HttpPut(nameof(LegalUnit))]
        public IActionResult EditLegalUnit([FromBody] LegalUnitEditM data)
        {
            _statUnitService.EditLegalUnit(data);
            return NoContent();
        }

        [HttpPut(nameof(LocalUnit))]
        public IActionResult EditLocalUnit([FromBody] LocalUnitEditM data)
        {
            _statUnitService.EditLocalUnit(data);
            return NoContent();
        }
        [HttpPut(nameof(EnterpriseUnit))]
        public IActionResult EditEnterpriseUnit([FromBody] EnterpriseUnitEditM data)
        {
            _statUnitService.EditEnterpiseUnit(data);
            return NoContent();
        }

        [HttpPut("EnterpriseGroup")]
        public IActionResult EditEnterpriseGroup([FromBody] EnterpriseGroupEditM data)
        {
            _statUnitService.EditEnterpiseGroup(data);
            return NoContent();
        }
    }
}
