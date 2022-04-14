using System;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using nscreg.Server.Common;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Enums;
using EnterpriseGroup = nscreg.Data.Entities.EnterpriseGroup;
using LegalUnit = nscreg.Data.Entities.LegalUnit;
using LocalUnit = nscreg.Data.Entities.LocalUnit;
using StatUnitAnalysisRules = nscreg.Utilities.Configuration.StatUnitAnalysis.StatUnitAnalysisRules;
using AutoMapper;
using System.Net.Http;
using System.Net;
using System.Net.Http.Headers;

namespace nscreg.Server.Controllers
{
    /// <inheritdoc />
    /// <summary>
    /// Statistical Unit Controller
    /// </summary>
    [Route("api/[controller]")]
    public class StatUnitsController : Controller
    {
        private readonly SearchService _searchService;
        private readonly ViewService _viewService;
        private readonly CreateService _createService;
        private readonly EditService _editService;
        private readonly DeleteService _deleteService;
        private readonly HistoryService _historyService;
        private readonly IMapper _mapper;

        public StatUnitsController(SearchService searchService, ViewService viewService, CreateService createService,
            EditService editService, DeleteService deleteService, HistoryService historyService, IMapper mapper)
        {
            _searchService = searchService;
            _viewService = viewService;
            _createService = createService; // new CreateService(context, statUnitAnalysisRules, mandatoryFields, validationSettings, _mapper, shouldAnalyze: true);
            _editService = editService;
            _deleteService = deleteService;
            _historyService = historyService;
            _mapper = mapper;
        }

        /// <summary>
        /// The method of obtaining organizational communication
        /// </summary>
        /// <param name="id">Organization Communication Id</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetStatUnitById(int id) => Ok(await _viewService.GetStatUnitById(id));

        /// <summary>
        /// Method for getting stat. units by id
        /// </summary>
        /// <param name="id">Id stat. units</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id) => Ok(await _viewService.GetById(id));

        /// <summary>
        /// Stat search method. units
        /// </summary>
        /// <param name="query">Search query</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> Search([FromQuery] SearchQueryM query) =>
            Ok(await _searchService.Search(query, User.GetUserId()));

        /// <summary>
        /// Stat search method. units by code
        /// </summary>
        /// <param name="type">Unit Stat Type</param>
        /// <param name="code">Search code</param>
        /// <param name="regId">Registration Id</param>
        /// <param name="isDeleted">Delete flag</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView, SystemFunctions.LinksView)]
        public async Task<IActionResult> SearchByStatId(StatUnitTypes type, string code, int regId, bool isDeleted=false) =>
            Ok(await _searchService.Search(type, code, User.GetUserId(), regId, isDeleted));

        /// <summary>
        /// Stat search method. units by name
        /// </summary>
        /// <param name="wildcard">Search pattern</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> SearchByWildcard(string wildcard) =>
            Ok(await _searchService.SearchByWildcard(wildcard));

        /// <summary>
        /// The method of obtaining the organizational communication tree
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetOrgLinksTree(int id) =>
            Ok(await _viewService.GetOrgLinksTree(id));

        /// <summary>
        /// The method of obtaining the history of stat. units
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <param name="id">Id stat. units</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> History(StatUnitTypes type, int id) =>
            Ok(await _historyService.ShowHistoryAsync(type, id));

        /// <summary>
        /// A method of obtaining a detailed history of stat. units
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <param name="id">Id stat. units</param>
        /// <param name="isHistory">Is the stat. historical unit</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}/{isHistory}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> HistoryDetails(StatUnitTypes type, int id, bool isHistory) =>
            Ok(await _historyService.ShowHistoryDetailsAsync(type, id, User.GetUserId(), isHistory));

        /// <summary>
        /// Method for obtaining a new entity
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}")]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> GetNewEntity(StatUnitTypes type) =>
            Ok(await _viewService.GetViewModel(null, type, User.GetUserId(), ActionsEnum.Create));

        /// <summary>
        /// Method for getting stat. units by id
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <param name="id">Id stat. units</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetUnitById(StatUnitTypes type, string id)
        {
            int.TryParse(id, out int result);
            return Ok(await _viewService.GetViewModel(result, type, User.GetUserId(), ActionsEnum.Edit));
        }

        /// <summary>
        /// Method for getting stat. units by Id and type
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <param name="id">Id stat. units</param>
        /// <returns></returns>
        [HttpGet("{type:int}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetEntityById(StatUnitTypes type, string id)
        {
            int.TryParse(id, out int result);
            return Ok(await _viewService.GetUnitByIdAndType(result, type, User.GetUserId(), true));
        }

        /// <summary>
        /// Stat removal method. units
        /// </summary>
        /// <param name="type">Type of stat. units</param>
        /// <param name="id">Id stat. units</param>
        /// <returns></returns>
        [HttpDelete("{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public IActionResult Delete(StatUnitTypes type, int id)
        {
            try
            {
                _deleteService.DeleteUndelete(type, id, true, User.GetUserId());
                return NoContent();
            }
            catch (UnauthorizedAccessException)
            {
                return Forbid();
            }
          
        }

        /// <summary>
        /// Legal Unit Creation Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPost(nameof(LegalUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateLegalUnit([FromBody] LegalUnitCreateM data)
        {
            if (data.EntRegIdDate == null)
            {
                data.EntRegIdDate = DateTime.Now;
            }
            var result = await _createService.CreateLegalUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Local Unit Creation Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPost(nameof(LocalUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateLocalUnit([FromBody] LocalUnitCreateM data)
        {
            var result = await _createService.CreateLocalUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Enterprise Creation Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPost(nameof(EnterpriseUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateEnterpriseUnit([FromBody] EnterpriseUnitCreateM data)
        {
            var result = await _createService.CreateEnterpriseUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Method for creating an enterprise group
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPost(nameof(EnterpriseGroup))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateEnterpriseGroup([FromBody] EnterpriseGroupCreateM data)
        {
            var result = await _createService.CreateEnterpriseGroup(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Legal Unit Editing Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPut(nameof(LegalUnit))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditLegalUnit([FromBody] LegalUnitEditM data)
        {
            var result = await _editService.EditLegalUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult)NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Local Unit Editing Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPut(nameof(LocalUnit))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditLocalUnit([FromBody] LocalUnitEditM data)
        {
            var result = await _editService.EditLocalUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Enterprise Editing Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPut(nameof(EnterpriseUnit))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditEnterpriseUnit([FromBody] EnterpriseUnitEditM data)
        {
            var result = await _editService.EditEnterpriseUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Enterprise Group Editing Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPut(nameof(EnterpriseGroup))]
        [SystemFunction(SystemFunctions.StatUnitEdit)]
        public async Task<IActionResult> EditEnterpriseGroup([FromBody] EnterpriseGroupEditM data)
        {
            var result = await _editService.EditEnterpriseGroup(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Method for obtaining code and sector name
        /// </summary>
        /// <param name="sectorCodeId">Sector Id</param>
        /// <returns></returns>
        [HttpGet("[action]/{sectorCodeId}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetSector(int sectorCodeId) =>
            Ok(await _viewService.GetSectorCodeNameBySectorId(sectorCodeId));

        /// <summary>
        /// The method of obtaining the code and name of the legal form
        /// </summary>
        /// <param name="legalFormId">Id Legal Form</param>
        /// <returns></returns>
        [HttpGet("[action]/{legalFormId}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetLegalForm(int legalFormId) =>
            Ok(await _viewService.GetLegalFormCodeNameByLegalFormId(legalFormId));

        [HttpGet("[action]")]
        [AllowAnonymous]
        public async Task<IActionResult> ValidateStatId(int? unitId, StatUnitTypes unitType, string value) =>
            Ok(await _searchService.ValidateStatIdUniquenessAsync(unitId, unitType, value));

        [HttpGet("[action]")]
        public async Task<FileResult> DownloadStatUnitEnterpriseCsv()
        {
            var csvBytes = await _viewService.DownloadStatUnitEnterprise();
            return File(csvBytes, System.Net.Mime.MediaTypeNames.Application.Octet, "StatUnitEnterprise.csv");
        }


        [HttpGet("[action]")]
        public async Task<FileResult> DownloadStatUnitLocalCsv()
        {
            var csvBytes = await _viewService.DownloadStatUnitLocal();
            return File(csvBytes, System.Net.Mime.MediaTypeNames.Application.Octet, "StatUnitLocal.csv");
        }
    }
}
