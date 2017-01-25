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

        [HttpGet("[action]/{type}")]
        public IActionResult GetStatUnits(StatUnitTypes type)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return Ok(_statUnitService.GetLocallUnitsLookup());
                case StatUnitTypes.LegalUnit:
                    return Ok(_statUnitService.GetLegalUnitsLookup());
                case StatUnitTypes.EnterpriseUnit:
                    return Ok(_statUnitService.GetEnterpriseUnitsLookup());
                case StatUnitTypes.EnterpriseGroup:
                    return Ok(_statUnitService.GetEnterpriseGroupsLookup());
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        [HttpGet("[action]/{type}")]
        public IActionResult GetNewEntity(StatUnitTypes type)
        {
            var unit = _statUnitService.GetViewModel(null, type,
                User.FindFirst(CustomClaimTypes.DataAccessAttributes)?.Value.Split(','));
            return Ok(unit);
        }


        [HttpGet("{type:int}/{id}")]
        public IActionResult GetEntityById(StatUnitTypes type, int id)
        {
            var unit = _statUnitService.GetUnitByIdAndType(id, type,
                User.FindFirst(CustomClaimTypes.DataAccessAttributes)?.Value.Split(','));
            return Ok(unit);
        }

       
        [HttpDelete("{unitType}/{id}")]
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
            return NoContent();
        }

        [HttpPost("LocalUnit")]
        public IActionResult CreateLocalUnit([FromBody] LocalUnitCreateM data)
        {
            _statUnitService.CreateLocalUnit(data);
            return NoContent();
        }

        [HttpPost("EnterpriseUnit")]
        public IActionResult CreateEnterpriseUnit([FromBody] EnterpriseUnitCreateM data)
        {
            _statUnitService.CreateEnterpriseUnit(data);
            return NoContent();
        }

        [HttpPost("EnterpriseGroup")]
        public IActionResult CreateEnterpriseGroup([FromBody] EnterpriseGroupCreateM data)
        {
            _statUnitService.CreateEnterpriseGroupUnit(data);
            return NoContent();
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
