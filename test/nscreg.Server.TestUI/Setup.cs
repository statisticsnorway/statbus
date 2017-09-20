using System.IO;
using Microsoft.Extensions.Configuration;
using OpenQA.Selenium.Chrome;
using OpenQA.Selenium.Remote;

namespace nscreg.Server.TestUI
{
    public static class Setup
    {
        internal static RemoteWebDriver CreateWebDriver()
        {
            var basePath = Path.Combine(System.AppContext.BaseDirectory, @"..\..\..");
            var appsettings = new ConfigurationBuilder()
                .SetBasePath(basePath)
                .AddJsonFile("appsettings.json")
                .AddUserSecrets("aspnet-nscreg.Server.TestUI-20160202011040")
                .Build();

            return new ChromeDriver($@"{basePath}\") {Url = appsettings.GetSection("Url").Value};
        }
    }
}
