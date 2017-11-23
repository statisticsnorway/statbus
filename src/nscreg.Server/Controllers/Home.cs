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
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Core;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.Localization;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Главный контроллер для входа в систему
    /// </summary>
    public class HomeController : Controller
    {
        private readonly IHostingEnvironment _env;
        private readonly IAntiforgery _antiforgery;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly LocalizationSettings _localization;
        private readonly NSCRegDbContext _ctx;
        private dynamic _assets;

        public HomeController(
            IHostingEnvironment env,
            IAntiforgery antiforgery,
            LocalizationSettings localization,
            DbMandatoryFields dbMandatoryFields,
            NSCRegDbContext db)
        {
            _env = env;
            _antiforgery = antiforgery;
            _dbMandatoryFields = dbMandatoryFields;
            _localization = localization;
            _ctx = db;
        }

        /// <summary>
        /// Главный метод обработчик для входа в систему
        /// </summary>
        /// <returns></returns>
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
            var dataAccessAttributes = DataAccessPermissions.Combine(roles
                .Select(r => r.StandardDataAccessArray));
               
            var systemFunctions = roles
                .SelectMany(r => r.AccessToSystemFunctionsArray)
                .Distinct()
                .Select(x => ((SystemFunctions) x).ToString());

            ViewData["assets:main:js"] = (string) _assets.main.js;
            ViewData["userName"] = User.Identity.Name;
            ViewData["dataAccessAttributes"] = JsonConvert.SerializeObject(dataAccessAttributes);
            ViewData["systemFunctions"] = string.Join(",", systemFunctions);
            ViewData["mandatoryFields"] = JsonConvert.SerializeObject(_dbMandatoryFields);
            ViewData["locales"] = JsonConvert.SerializeObject(_localization.Locales);
            ViewData["defaultLocale"] = _localization.DefaultKey;
            ViewData["resources"] = JsonConvert.SerializeObject(Localization.AllResources);
            ViewData["roles"] = JsonConvert.SerializeObject(roles.Select(x => x.Name).ToArray());

            // Send the request token as a JavaScript-readable cookie
            var tokens = _antiforgery.GetAndStoreTokens(Request.HttpContext);
            Response.Cookies.Append("XSRF-TOKEN", tokens.RequestToken, new CookieOptions {HttpOnly = false});

            return View("~/Views/Index.cshtml");
        }
    }
}
