using Microsoft.AspNetCore.Mvc;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Контроллер аттрибута доступа
    /// </summary>
    [Route("api/[controller]")]
    public class AccessAttributesController : Controller
    {
        /// <summary>
        /// Метод возвращающий все системные функции
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public IActionResult SystemFunctions() => Ok(AccessAttributesService.GetAllSystemFunctions());

        /// <summary>
        /// Метод возвращающий все аттрибуты доступа данных
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public IActionResult DataAttributes() => Ok(AccessAttributesService.GetAllDataAccessAttributes());
    }
}
