using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.Regions;
using nscreg.Server.Common.Services;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Region controller
    /// </summary>
    [Route("api/[controller]")]
    public class RegionsController : Controller
    {
        private readonly RegionService _regionsService;

        public RegionsController(RegionService regionsService)
        {
            _regionsService = regionsService;
        }

        /// <summary>
        /// Method to get a list of regions
        /// </summary>
        /// <param name="model">Request Model</param>
        /// <returns></returns>
        [HttpGet]
        [SystemFunction(
            SystemFunctions.StatUnitCreate,
            SystemFunctions.StatUnitEdit,
            SystemFunctions.StatUnitView,
            SystemFunctions.RegionsView)]
        public async Task<IActionResult> List([FromQuery] PaginatedQueryM model) =>
            Ok(await _regionsService.ListAsync(model));

        /// <summary>
        /// Region acquisition method
        /// </summary>
        /// <param name="id">Id</param>
        /// <returns></returns>
        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RegionsView)]
        public async Task<IActionResult> List(int id) => Ok(await _regionsService.GetAsync(id));

        /// <summary>
        /// Region creation method
        /// </summary>
        /// <param name="data">Data</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.RegionsCreate, SystemFunctions.RegionsView)]
        public async Task<IActionResult> Create([FromBody] RegionM data)
        {
            var region = await _regionsService.CreateAsync(data);
            return Created($"api/regions/{region.Id}", region);
        }

        /// <summary>
        /// Region Editing Method
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="data">Data</param>
        /// <returns></returns>
        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RegionsEdit)]
        public async Task<IActionResult> Edit(int id, [FromBody] RegionM data)
        {
            await _regionsService.EditAsync(id, data);
            return NoContent();
        }

        /// <summary>
        /// Distance Switching Method
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="delete">Remoteness flag</param>
        /// <returns></returns>
        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RegionsDelete)]
        public async Task<IActionResult> ToggleDelete(int id, bool delete = false)
        {
            await _regionsService.DeleteUndelete(id, delete);
            return NoContent();
        }

        /// <summary>
        /// Region Search Method
        /// </summary>
        /// <param name="wildcard">Search pattern</param>
        /// <param name="limit">Limitation</param>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> Search(string wildcard, int limit = 10) =>
            Ok(await _regionsService.ListAsync(
                x =>
                    x.Code.Contains(wildcard)
                    || x.Name.ToLower().Contains(wildcard.ToLower())
                    || x.AdminstrativeCenter.Contains(wildcard),
                limit));

        /// <summary>
        /// Address List Method
        /// </summary>
        /// <param name="code">Region code</param>
        /// <returns></returns>
        [HttpGet("{code}")]
        public async Task<IActionResult> GetAddress(string code)
        {
            if (!Regex.IsMatch(code, @"\d{14}"))
                return NotFound();
            var digitCounts = new[] {3, 5, 8, 11, 14}; //number of digits to parse
            var lst = new List<string>();
            foreach (var item in digitCounts)
            {
                var searchCode = code.Substring(0, item);
                var region = await _regionsService.GetAsync(searchCode);
                lst.Add(region?.Name ?? "");
            }
            return Ok(lst);
        }

        /// <summary>
        /// Method for treating the entire tree of regions
        /// </summary>
        /// <returns></returns>
        [HttpGet("[action]")]
        public async Task<IActionResult> GetAllRegionTree() => Ok(await _regionsService.GetAllRegionTreeAsync(nameof(Resource.AllRegions)));
    }
}
