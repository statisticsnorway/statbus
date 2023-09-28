using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Localization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Common;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.Localization;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums.Predicate;
using static Newtonsoft.Json.JsonConvert;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Main controller for login
    /// </summary>
    public class HomeController : Controller
    {
        private readonly IWebHostEnvironment _env;
        private readonly IAntiforgery _antiforgery;
        private readonly DbMandatoryFields _dbMandatoryFields;
        private readonly LocalizationSettings _localization;
        private readonly ReportingSettings _reportingSettings;
        private readonly ValidationSettings _validationSettings;
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly NSCRegDbContext _ctx;
        private dynamic _assets;

        public HomeController(
            IWebHostEnvironment env,
            IAntiforgery antiforgery,
            LocalizationSettings localization,
            DbMandatoryFields dbMandatoryFields,
            ReportingSettings reportingSettings,
            ValidationSettings validationSettings,
            StatUnitAnalysisRules analysisRules,
            NSCRegDbContext db)
        {
            _env = env;
            _antiforgery = antiforgery;
            _dbMandatoryFields = dbMandatoryFields;
            _localization = localization;
            _reportingSettings = reportingSettings;
            _validationSettings = validationSettings;
            _analysisRules = analysisRules;
            _ctx = db;
        }

        /// <summary>
        /// Main method handler for logging in
        /// </summary>
        /// <returns></returns>
        public async Task<IActionResult> Index()
        {
            if (_env.IsDevelopment() || _assets == null)
            {
                var assetsFileName = Path.Combine(_env.WebRootPath, "./assets.json");
                using (var stream = System.IO.File.OpenRead(assetsFileName))
                using (var reader = new StreamReader(stream))
                {
                    var json = await reader.ReadToEndAsync();
                    _assets = DeserializeObject(json);
                }
            }

            var allUserIdentity = await _ctx.Users
                .Include(x => x.UserRoles)
                .ThenInclude(x=>x.Role)
                .ToListAsync();
            var user = allUserIdentity.FirstOrDefault(u => u.Login == User.Identity.Name);
            var allRole = await _ctx.Roles.ToListAsync();
            var roles = allRole
                .Where(r => user.UserRoles.Any(ur => ur.RoleId == r.Id)).ToList();
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
            ViewData["Language1"] = _localization.Language1;
            ViewData["Language2"] = _localization.Language2;
            ViewData["resources"] = SerializeObject(Localization.AllResources);
            ViewData["roles"] = SerializeObject(roles.Select(x => x.Name).ToArray());
            ViewData["reportingSettings"] = SerializeObject(_reportingSettings);
            ViewData["validationSettings"] = SerializeObject(_validationSettings);
            ViewData["sampleFramePredicateFieldMeta"] = SerializeObject(typeof(FieldEnum)
                .GetMembers()
                .Where(x => x.GetCustomAttributes<OperationAllowedAttribute>().Any())
                .Select(ToPredicateFieldMeta)
                .ToImmutableDictionary());
            ViewData["analysisRules"] = SerializeObject(_analysisRules);

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
        /// <summary>
        /// Change global culture
        /// </summary>
        /// <param name="locale"></param>
        /// <returns></returns>
        [AllowAnonymous]
        [HttpGet("[action]")]
        public IActionResult ChangeCulture(string locale)
        {
            CultureInfo.DefaultThreadCurrentCulture = new CultureInfo(locale == "en-GB" ? string.Empty : locale);
            Response.Cookies.Append(
                CookieRequestCultureProvider.DefaultCookieName,
                CookieRequestCultureProvider.MakeCookieValue(new RequestCulture(locale)),
                new CookieOptions { Expires = DateTimeOffset.UtcNow.AddMonths(1) }
            );
            return Ok();
        }
    }
}
