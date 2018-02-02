using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Core;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.Localization;
using nscreg.Utilities.Enums.Predicate;
using static Newtonsoft.Json.JsonConvert;

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
        private readonly ReportingSettings _reportingSettings;
        private readonly NSCRegDbContext _ctx;
        private dynamic _assets;

        public HomeController(
            IHostingEnvironment env,
            IAntiforgery antiforgery,
            LocalizationSettings localization,
            DbMandatoryFields dbMandatoryFields,
            ReportingSettings reportingSettings,
            NSCRegDbContext db)
        {
            _env = env;
            _antiforgery = antiforgery;
            _dbMandatoryFields = dbMandatoryFields;
            _localization = localization;
            _reportingSettings = reportingSettings;
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
                    _assets = DeserializeObject(json);
                }
            }

            var user = await _ctx.Users
                .Include(x => x.Roles)
                .FirstAsync(u => u.Login == User.Identity.Name);
            var roles = await _ctx.Roles
                .Where(r => user.Roles.Any(ur => ur.RoleId == r.Id)).ToListAsync();
            if (user == null || !roles.Any()) return RedirectToAction("LogOut", "Account");
            var dataAccessAttributes = DataAccessPermissions.Combine(
                roles.Select(r => r.StandardDataAccessArray));

            var systemFunctions = roles
                .SelectMany(r => r.AccessToSystemFunctionsArray)
                .Distinct()
                .Select(x => ((SystemFunctions) x).ToString());

            ViewData["assets:main:js"] = (string) _assets.main.js;
            ViewData["userName"] = User.Identity.Name;
            ViewData["dataAccessAttributes"] = SerializeObject(dataAccessAttributes);
            ViewData["systemFunctions"] = string.Join(",", systemFunctions);
            ViewData["mandatoryFields"] = SerializeObject(_dbMandatoryFields);
            ViewData["locales"] = SerializeObject(_localization.Locales);
            ViewData["defaultLocale"] = _localization.DefaultKey;
            ViewData["resources"] = SerializeObject(Localization.AllResources);
            ViewData["roles"] = SerializeObject(roles.Select(x => x.Name).ToArray());
            ViewData["reportingSettings"] = SerializeObject(_reportingSettings);
            ViewData["sampleFramePredicateFieldMeta"] = SerializeObject(typeof(FieldEnum)
                .GetMembers()
                .Where(x => x.GetCustomAttributes<OperationAllowedAttribute>().Any())
                .Select(ToPredicateFieldMeta)
                .ToImmutableDictionary());

            // Send the request token as a JavaScript-readable cookie
            var tokens = _antiforgery.GetAndStoreTokens(Request.HttpContext);
            Response.Cookies.Append("XSRF-TOKEN", tokens.RequestToken, new CookieOptions {HttpOnly = false});

            return View("~/Views/Index.cshtml");

            KeyValuePair<int, object> ToPredicateFieldMeta(MemberInfo x)
            {
                var field = (FieldEnum) Enum.Parse(typeof(FieldEnum), x.Name);
                return new KeyValuePair<int, object>(
                    (int) field,
                    new
                    {
                        value = field.ToString(),
                        operations = x.GetCustomAttribute<OperationAllowedAttribute>().AllowedOperations,
                    });
            }
        }
    }
}
