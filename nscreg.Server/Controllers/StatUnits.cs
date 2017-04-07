using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Data.Constants;
using System;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Extension;

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
        public async Task<IActionResult> Search([FromQuery] SearchQueryM query)
            => Ok(await _statUnitService.Search(query, User.GetUserId()));

        [HttpGet("[action]/{type}/{id}")]
        public async Task<IActionResult> History(StatUnitTypes type, int id)
        {
            return Ok( await _statUnitService.ShowHistoryAsync(type, id));
        }

        [HttpGet("[action]/{type}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
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
        public async Task<IActionResult> GetNewEntity(StatUnitTypes type)
            => Ok(await _statUnitService.GetViewModel(null, type, User.GetUserId()));

        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetUnitById(StatUnitTypes type, int id)
            => Ok(await _statUnitService.GetViewModel(id, type, User.GetUserId()));

        [HttpGet("{type:int}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetEntityById(StatUnitTypes type, int id)
            => Ok(await _statUnitService.GetUnitByIdAndType(id, type, User.GetUserId(), true));

        [HttpDelete("{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public IActionResult Delete(StatUnitTypes type, int id)
        {
            _statUnitService.DeleteUndelete(type, id, true, User.GetUserId());
            return NoContent();
        }

        [HttpPost(nameof(LegalUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateLegalUnit([FromBody] LegalUnitCreateM data)
        {
            await _statUnitService.CreateLegalUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPost(nameof(LocalUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateLocalUnit([FromBody] LocalUnitCreateM data)
        {
            await _statUnitService.CreateLocalUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPost(nameof(EnterpriseUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateEnterpriseUnit([FromBody] EnterpriseUnitCreateM data)
        {
            await _statUnitService.CreateEnterpriseUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPost(nameof(EnterpriseGroup))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async  Task<IActionResult> CreateEnterpriseGroup([FromBody] EnterpriseGroupCreateM data)
        {
            await _statUnitService.CreateEnterpriseGroupUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPut(nameof(LegalUnit))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditLegalUnit([FromBody] LegalUnitEditM data)
        {
            await _statUnitService.EditLegalUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPut(nameof(LocalUnit))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditLocalUnit([FromBody] LocalUnitEditM data)
        {
            await _statUnitService.EditLocalUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPut(nameof(EnterpriseUnit))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditEnterpriseUnit([FromBody] EnterpriseUnitEditM data)
        {
            await _statUnitService.EditEnterpiseUnit(data, User.GetUserId());
            return NoContent();
        }

        [HttpPut(nameof(EnterpriseGroup))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditEnterpriseGroup([FromBody] EnterpriseGroupEditM data)
        {
            await _statUnitService.EditEnterpiseGroup(data, User.GetUserId());
            return NoContent();
        }
    }
}
