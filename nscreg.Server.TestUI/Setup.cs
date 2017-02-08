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

            return new ChromeDriver($@"{basePath}\WebDrivers\") {Url = appsettings.GetSection("Url").Value};
        }

#pragma warning disable RECS0154 // Parameter is never used
        // ReSharper disable once UnusedMember.Global
        // ReSharper disable once UnusedParameter.Global
        public static void Main(string[] args)
#pragma warning restore RECS0154 // Parameter is never used
        {
        }
    }
}
