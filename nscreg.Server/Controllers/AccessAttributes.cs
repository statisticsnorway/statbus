using Microsoft.AspNetCore.Mvc;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class AccessAttributesController : Controller
    {
        [HttpGet("[action]")]
        public IActionResult SystemFunctions() => Ok(AccessAttributesService.GetAllSystemFunctions());

        [HttpGet("[action]")]
        public IActionResult DataAttributes() => Ok(AccessAttributesService.GetAllDataAccessAttributes());
    }
}
