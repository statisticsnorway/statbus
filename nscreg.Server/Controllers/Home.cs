using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Newtonsoft.Json;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.ReadStack;

namespace nscreg.Server.Controllers
{
    public class HomeController : Controller
    {
        private readonly IHostingEnvironment _env;
        private readonly IAntiforgery _antiforgery;
        private readonly ReadContext _ctx;
        private dynamic _assets;

        public HomeController(IHostingEnvironment env, IAntiforgery antiforgery, NSCRegDbContext db)
        {
            _env = env;
            _antiforgery = antiforgery;
            _ctx = new ReadContext(db);
        }

        public async Task<IActionResult> Index()
        {
            if (_env.IsDevelopment() || _assets == null)
            {
                var assetsFileName = Path.Combine(_env.WebRootPath, "./dist/assets.json");
                using (var stream = System.IO.File.OpenRead(assetsFileName))
                using (var reader = new StreamReader(stream))
                {
                    var json = await reader.ReadToEndAsync();
                    _assets = JsonConvert.DeserializeObject(json);
                }
            }

            var user = _ctx.Users
                .Include(x => x.Roles)
                .FirstOrDefault(u => u.Login == User.Identity.Name);
            var roles = _ctx.Roles
                .Where(r => user.Roles.Any(ur => ur.RoleId == r.Id));
            var dataAccessAttributes = roles
                .SelectMany(r => r.StandardDataAccessArray)
                .Concat(user.DataAccessArray)
                .Distinct();
            var systemFunctions = roles
                .SelectMany(r => r.AccessToSystemFunctionsArray)
                .Distinct()
                .Select(x => ((SystemFunctions) x).ToString());

            ViewData["assets:main:js"] = (string) _assets.main.js;
            ViewData["userName"] = User.Identity.Name;
            ViewData["dataAccessAttributes"] = string.Join(",", dataAccessAttributes);
            ViewData["systemFunctions"] = string.Join(",", systemFunctions);
            ViewData["allLanguages"] = JsonConvert.SerializeObject(Localization.AllResources);

            // Send the request token as a JavaScript-readable cookie
            var tokens = _antiforgery.GetAndStoreTokens(Request.HttpContext);
            Response.Cookies.Append("XSRF-TOKEN", tokens.RequestToken, new CookieOptions {HttpOnly = false});

            return View("~/Views/Index.cshtml");
        }
    }
}
