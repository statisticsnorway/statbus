using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.Addresses;
using nscreg.Server.Models.Soates;
using nscreg.Server.Services;
using nscreg.Server.Services.Contracts;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class SoatesController : Controller
    {
        private readonly ISoateService _soateService;

        public SoatesController(NSCRegDbContext context)
        {
            _soateService = new SoateService(context);
        }

        [HttpGet] //api/soate?code=123&limit=50
        public async Task<IActionResult> Get(string code, int limit = 10)
            => Ok(await _soateService.GetAsync(x => x.Code.Contains(code), limit));

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
                var soate = await _soateService.GetByCode(searchCode);
                lst.Add(soate?.Name ?? "");
            }
            return Ok(lst);
        }
    }
}
