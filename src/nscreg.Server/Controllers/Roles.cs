using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.Roles;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер ролей пользователя
    /// </summary>
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly RoleService _roleService;

        public RolesController(NSCRegDbContext db)
        {
            _roleService = new RoleService(db);
        }

        /// <summary>
        /// Метод получения списка ролей
        /// </summary>
        /// <param name="model">Модель запроса</param>
        /// <param name="onlyActive">Флаг активности роли</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.RoleView, SystemFunctions.UserEdit, SystemFunctions.UserCreate, SystemFunctions.UserView)]
        public IActionResult GetAllRoles(
                [FromQuery] PaginatedQueryM model,
                bool onlyActive = true) =>
            Ok(_roleService.GetAllPaged(model, onlyActive));

        /// <summary>
        /// Метод получения роли
        /// </summary>
        /// <param name="id">Id роли</param>
        /// <returns></returns>
        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RoleView)]
        public IActionResult GetRoleById(string id) => Ok(_roleService.GetRoleById(id));

        /// <summary>
        /// Метод создания роли
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.RoleCreate)]
        public IActionResult Create([FromBody] RoleSubmitM data)
        {
            var createdRoleVm = _roleService.Create(data);
            return Created($"api/roles/{createdRoleVm.Id}", createdRoleVm);
        }

        /// <summary>
        /// Метод редактирования роли
        /// </summary>
        /// <param name="id">Id роли</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RoleEdit)]
        public IActionResult Edit(string id, [FromBody] RoleSubmitM data)
        {
            _roleService.Edit(id, data);
            return NoContent();
        }

        /// <summary>
        /// Метод переключения удалённости роли
        /// </summary>
        /// <param name="id">Id роли</param>
        /// <param name="status">Статус роли</param>
        /// <returns></returns>
        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RoleDelete)]
        public async Task<IActionResult> ToggleDelete(string id, RoleStatuses status)
        {
            await _roleService.ToggleSuspend(id, status);
            return NoContent();
        }

        /// <summary>
        /// Метод получения активности дерева ролей
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> FetchActivityTree(int parentId=0) => Ok(await _roleService.FetchActivityTreeAsync(parentId));
    }
}
