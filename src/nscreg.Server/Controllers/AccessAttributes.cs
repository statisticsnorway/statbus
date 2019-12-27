using Microsoft.AspNetCore.Mvc;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Access attribute controller
    /// </summary>
    [Route("api/[controller]")]
    public class AccessAttributesController : Controller
    {
        /// <summary>
        /// Method returning all system functions
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public IActionResult SystemFunctions() => Ok(AccessAttributesService.GetAllSystemFunctions());

        /// <summary>
        /// Method returning all data access attributes
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public IActionResult DataAttributes() => Ok(AccessAttributesService.GetAllDataAccessAttributes());
    }
}
