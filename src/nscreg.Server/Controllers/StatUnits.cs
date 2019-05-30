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

namespace nscreg.Server.Controllers
{
    /// <inheritdoc />
    /// <summary>
    /// Контроллер статистических единиц
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

        public StatUnitsController(NSCRegDbContext context, StatUnitAnalysisRules statUnitAnalysisRules,
            DbMandatoryFields mandatoryFields, ValidationSettings validationSettings)
        {
            _searchService = new SearchService(context);
            _viewService = new ViewService(context, mandatoryFields);
            _createService = new CreateService(context, statUnitAnalysisRules, mandatoryFields, validationSettings);
            _editService = new EditService(context, statUnitAnalysisRules, mandatoryFields, validationSettings);
            _deleteService = new DeleteService(context);
            _historyService = new HistoryService(context);
        }

        /// <summary>
        /// Метод получения организационной связи
        /// </summary>
        /// <param name="id">Id организационной связи</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetStatUnitById(int id) => Ok(await _viewService.GetStatUnitById(id));

        /// <summary>
        /// Метод получения стат. единицы по Id
        /// </summary>
        /// <param name="id">Id стат. еденицы</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetById(int id) => Ok(await _viewService.GetById(id));

        /// <summary>
        /// Метод поиска стат. единицы
        /// </summary>
        /// <param name="query">Запрос поиска</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> Search([FromQuery] SearchQueryM query) =>
            Ok(await _searchService.Search(query, User.GetUserId()));

        /// <summary>
        /// Метод поиска стат. единицы по коду
        /// </summary>
        /// <param name="type">Тип стат юнита</param>
        /// <param name="code">Код поиска</param>
        /// <param name="regId">Регистрационный Id</param>
        /// <param name="isDeleted">Флаг удаления</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView, SystemFunctions.LinksView)]
        public async Task<IActionResult> SearchByStatId(StatUnitTypes type, string code, int regId, bool isDeleted=false) =>
            Ok(await _searchService.Search(type, code, User.GetUserId(), regId, isDeleted));

        /// <summary>
        /// Метод поиска стат. единицы по имени
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> SearchByWildcard(string wildcard) =>
            Ok(await _searchService.SearchByWildcard(wildcard));

        /// <summary>
        /// Метод получения дерева организационной связи
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetOrgLinksTree(int id) =>
            Ok(await _viewService.GetOrgLinksTree(id));

        /// <summary>
        /// Метод получения истории стат. единицы
        /// </summary>
        /// <param name="type">Тип стат. еденицы</param>
        /// <param name="id">Id стат. еденицы</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> History(StatUnitTypes type, int id) =>
            Ok(await _historyService.ShowHistoryAsync(type, id));

        /// <summary>
        /// Метод получения подробной истории стат. единицы
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <param name="isHistory">Является ли стат. единица исторической</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}/{isHistory}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> HistoryDetails(StatUnitTypes type, int id, bool isHistory) =>
            Ok(await _historyService.ShowHistoryDetailsAsync(type, id, User.GetUserId(), isHistory));

        /// <summary>
        /// Метод получения новой сущности
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}")]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> GetNewEntity(StatUnitTypes type) =>
            Ok(await _viewService.GetViewModel(null, type, User.GetUserId(), ActionsEnum.Create));

        /// <summary>
        /// Метод получения стат. единицы по Id
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetUnitById(StatUnitTypes type, string id)
        {
            int.TryParse(id, out int result);
            return Ok(await _viewService.GetViewModel(result, type, User.GetUserId(), ActionsEnum.Edit));
        }

        /// <summary>
        /// Метод получения стат. единицы по Id и типу
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <returns></returns>
        [HttpGet("{type:int}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetEntityById(StatUnitTypes type, string id)
        {
            int.TryParse(id, out int result);
            return Ok(await _viewService.GetUnitByIdAndType(result, type, User.GetUserId(), true));
        }

        /// <summary>
        /// Метод удаления стат. единицы
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
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
        /// Метод создания правовой единицы
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPost(nameof(LegalUnit))]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> CreateLegalUnit([FromBody] LegalUnitCreateM data)
        {
            var result = await _createService.CreateLegalUnit(data, User.GetUserId());
            if (result != null && result.ContainsKey(nameof(UserAccess.UnauthorizedAccess)))
            {
                return Forbid();
            }
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
        }

        /// <summary>
        /// Метод создания местной единицы
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод создания предприятия
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод создания группы предприятия
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод редактирования правовой единицы
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод редактирования местной единицы
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод редактирования предприятия
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод редактирования группы предприятия
        /// </summary>
        /// <param name="data">Данные</param>
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
        /// Метод получения кода и имени сектора
        /// </summary>
        /// <param name="sectorCodeId">Id сектора</param>
        /// <returns></returns>
        [HttpGet("[action]/{sectorCodeId}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetSector(int sectorCodeId) =>
            Ok(await _viewService.GetSectorCodeNameBySectorId(sectorCodeId));

        /// <summary>
        /// Метод получения кода и имени легал формы
        /// </summary>
        /// <param name="legalFormId">Id легал формы</param>
        /// <returns></returns>
        [HttpGet("[action]/{legalFormId}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetLegalForm(int legalFormId) =>
            Ok(await _viewService.GetLegalFormCodeNameByLegalFormId(legalFormId));

        [HttpGet("[action]")]
        [AllowAnonymous]
        public async Task<IActionResult> ValidateStatId(int? unitId, StatUnitTypes unitType, string value) =>
            Ok(await _searchService.ValidateStatIdUniquenessAsync(unitId, unitType, value));
    }
}
