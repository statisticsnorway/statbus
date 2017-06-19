using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models;
using nscreg.Server.Models.Roles;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly RoleService _roleService;

        public RolesController(NSCRegDbContext db)
        {
            _roleService = new RoleService(db);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.RoleView, SystemFunctions.UserEdit, SystemFunctions.UserCreate, SystemFunctions.UserView)]
        public IActionResult GetAllRoles(
                [FromQuery] PaginationModel model,
                bool onlyActive = true)
            => Ok(_roleService.GetAllPaged(model, onlyActive));

        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RoleView)]
        public IActionResult GetRoleById(string id) => Ok(_roleService.GetRoleById(id));

        [HttpPost]
        [SystemFunction(SystemFunctions.RoleCreate)]
        public IActionResult Create([FromBody] RoleSubmitM data)
        {
            var createdRoleVm = _roleService.Create(data);
            return Created($"api/roles/{createdRoleVm.Id}", createdRoleVm);
        }

        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RoleEdit)]
        public IActionResult Edit(string id, [FromBody] RoleSubmitM data)
        {
            _roleService.Edit(id, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RoleDelete)]
        public async Task<IActionResult> ToggleDelete(string id, RoleStatuses status)
        {
            await _roleService.ToggleSuspend(id, status);
            return NoContent();
        }

        [HttpGet("[action]")]
        public async Task<IActionResult> FetchActivityTree() => Ok(await _roleService.FetchActivityTreeAsync());
    }
}
