using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Newtonsoft.Json;

namespace Server.Controllers
{
    public class HomeController : Controller
    {
        private readonly IHostingEnvironment _env;
        private dynamic _assets;

        public HomeController(IHostingEnvironment env)
        {
            _env = env;
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
            ViewData["assets:main:js"] = (string) _assets.main.js;
            return View();
        }
    }
}
