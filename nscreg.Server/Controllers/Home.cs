using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Newtonsoft.Json;

namespace nscreg.Server.Controllers
{
    public class HomeController : Controller
    {
        private readonly IHostingEnvironment _env;
        private readonly IAntiforgery _antiforgery;
        private dynamic _assets;

        public HomeController(IHostingEnvironment env, IAntiforgery antiforgery)
        {
            _env = env;
            _antiforgery = antiforgery;
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
            ViewData["assets:main:js"] = (string)_assets.main.js;

            // Send the request token as a JavaScript-readable cookie
            var tokens = _antiforgery.GetAndStoreTokens(Request.HttpContext);
            Response.Cookies.Append("XSRF-TOKEN", tokens.RequestToken, new CookieOptions { HttpOnly = false });

            return View("~/Views/Index.cshtml");
        }
    }
}
