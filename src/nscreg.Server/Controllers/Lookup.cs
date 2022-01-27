using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Services;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Object Search Controller
    /// </summary>
    [Route("api/[controller]")]
    public class LookupController : Controller
    {
        private readonly LookupService _lookupService;

        public LookupController(LookupService lookupService)
        {
            _lookupService = lookupService;
        }

        /// <summary>
        /// Method to get the search object
        /// </summary>
        /// <param name="lookup"></param>
        /// <returns></returns>
        [HttpGet("{lookup}")]
        public async Task<IActionResult> GetLookup(LookupEnum lookup) =>
            Ok(await _lookupService.GetLookupByEnum(lookup));

        /// <summary>
        /// Method for obtaining object search pagination
        /// </summary>
        /// <param name="lookup">Search Object</param>
        /// <param name="searchModel">Model search</param>
        /// <returns></returns>
        [HttpGet("paginated/{lookup}")]
        public async Task<IActionResult> GetPaginateLookup(LookupEnum lookup, [FromQuery] SearchLookupModel searchModel) =>
            Ok(await _lookupService.GetPaginateLookupByEnum(lookup, searchModel));

        /// <summary>
        /// Method for obtaining the search object by Id
        /// </summary>
        /// <param name="lookup">Search Object</param>
        /// <param name="ids">Id</param>
        /// <returns></returns>
        [HttpGet("{lookup}/[action]")]
        public async Task<IActionResult> GetById(LookupEnum lookup, [FromQuery] int[] ids) =>
            Ok(await _lookupService.GetById(lookup, ids));
    }
}
