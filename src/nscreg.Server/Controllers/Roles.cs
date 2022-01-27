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
    /// User role controller
    /// </summary>
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly RoleService _roleService;

        public RolesController(RoleService roleService)
        {
            _roleService = roleService;
        }

        /// <summary>
        /// Role List Method
        /// </summary>
        /// <param name="model">Request Model</param>
        /// <param name="onlyActive">Role Activity Flag</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.RoleView, SystemFunctions.UserEdit, SystemFunctions.UserCreate, SystemFunctions.UserView)]
        public IActionResult GetAllRoles(
                [FromQuery] PaginatedQueryM model,
                bool onlyActive = true) =>
            Ok(_roleService.GetAllPaged(model, onlyActive));

        /// <summary>
        /// Role acquisition method
        /// </summary>
        /// <param name="id">role Id</param>
        /// <returns></returns>
        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RoleView)]
        public IActionResult GetRoleById(string id) => Ok(_roleService.GetRoleVmById(id));

        /// <summary>
        /// Role Creation Method
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.RoleCreate)]
        public IActionResult Create([FromBody] RoleSubmitM data)
        {
            var createdRoleVm = _roleService.Create(data);
            return Created($"api/roles/{createdRoleVm.Id}", createdRoleVm);
        }

        /// <summary>
        /// Role Editing Method
        /// </summary>
        /// <param name="id">Role Id</param>
        /// <param name="data">Data</param>
        /// <returns></returns>
        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RoleEdit)]
        public IActionResult Edit(string id, [FromBody] RoleSubmitM data)
        {
            _roleService.Edit(id, data);
            return NoContent();
        }

        /// <summary>
        /// Role remoting method
        /// </summary>
        /// <param name="id">Role Id</param>
        /// <param name="status">Role status</param>
        /// <returns></returns>
        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RoleDelete)]
        public async Task<IActionResult> ToggleDelete(string id, RoleStatuses status)
        {
            await _roleService.ToggleSuspend(id, status);
            return NoContent();
        }

        /// <summary>
        /// The method of obtaining the activity of the role tree
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> FetchActivityTree(int parentId=0) => Ok(await _roleService.FetchActivityTreeAsync(parentId));
    }
}
