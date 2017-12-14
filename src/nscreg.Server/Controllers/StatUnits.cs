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
            DbMandatoryFields mandatoryFields)
        {
            _searchService = new SearchService(context);
            _viewService = new ViewService(context, mandatoryFields);
            _createService = new CreateService(context, statUnitAnalysisRules, mandatoryFields);
            _editService = new EditService(context, statUnitAnalysisRules, mandatoryFields);
            _deleteService = new DeleteService(context);
            _historyService = new HistoryService(context);
        }

        /// <summary>
        /// Метод получения организационной связи
        /// </summary>
        /// <param name="id">Id организационной связи</param>
        /// <returns></returns>
        [HttpGet("[action]/{id}")]
        public async Task<IActionResult> GetOrgLinkById(int id) => Ok(await _viewService.GetOrgLinkById(id));

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
        /// <param name="code">Код поиска</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView, SystemFunctions.LinksView)]
        public async Task<IActionResult> SearchByStatId(string code) =>
            Ok(await _searchService.Search(code));

        /// <summary>
        /// Метод поиска стат. единицы по имени
        /// </summary>
        /// <param name="wildcard">Шаблон поиска</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> SearchByStatName(string wildcard) =>
            Ok(await _searchService.SearchByName(wildcard));

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
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> HistoryDetails(StatUnitTypes type, int id) =>
            Ok(await _historyService.ShowHistoryDetailsAsync(type, id, User.GetUserId()));

        /// <summary>
        /// Метод получения новой сущности
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}")]
        [SystemFunction(SystemFunctions.StatUnitCreate)]
        public async Task<IActionResult> GetNewEntity(StatUnitTypes type) =>
            Ok(await _viewService.GetViewModel(null, type, User.GetUserId()));

        /// <summary>
        /// Метод получения стат. единицы по Id
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <returns></returns>
        [HttpGet("[action]/{type}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetUnitById(StatUnitTypes type, int id) =>
            Ok(await _viewService.GetViewModel(id, type, User.GetUserId()));

        /// <summary>
        /// Метод получения стат. единицы по Id и типу
        /// </summary>
        /// <param name="type">Тип стат. единицы</param>
        /// <param name="id">Id стат. единицы</param>
        /// <returns></returns>
        [HttpGet("{type:int}/{id}")]
        [SystemFunction(SystemFunctions.StatUnitView)]
        public async Task<IActionResult> GetEntityById(StatUnitTypes type, int id) =>
            Ok(await _viewService.GetUnitByIdAndType(id, type, User.GetUserId(), true));

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
            _deleteService.DeleteUndelete(type, id, true, User.GetUserId());
            return NoContent();
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
            return result == null ? (IActionResult) NoContent() : BadRequest(result);
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
    }
}
