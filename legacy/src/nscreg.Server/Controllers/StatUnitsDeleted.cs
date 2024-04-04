using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    ///  Stat units Delete Controller
    /// </summary>
    [Route("api/statunits/deleted")]
    public class StatUnitsDeletedController : Controller
    {
        private readonly DeleteService _deleteService;
        private readonly SearchService _searchService;

        public StatUnitsDeletedController(DeleteService deleteService, SearchService searchService)
        {
            _deleteService = deleteService;
            _searchService = searchService;
        }

        /// <summary>
        /// Method for getting deleted stats. units
        /// </summary>
        /// <param name="data">data</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public async Task<IActionResult> GetDeleted(SearchQueryM data) =>
            Ok(await _searchService.Search(data, User.GetUserId(), true));

        /// <summary>
        /// Deleted StatUnit Reset Method
        /// </summary>
        /// <param name="type">Stat uint type</param>
        /// <param name="regId">Registration Id</param>
        /// <returns></returns>
        [HttpDelete]
        [SystemFunction(SystemFunctions.StatUnitDelete)]
        public IActionResult Restore(StatUnitTypes type, int regId)
        {
            _deleteService.DeleteUndelete(type, regId, false, User.GetUserId());
            return NoContent();
        }
    }
}
