using Microsoft.Extensions.Configuration;

namespace nscreg.ServicesUtils
{
    public class Startup
    {
        public IConfigurationRoot Configuration { get; }

        public Startup(string slnPath, string projectPath, string fileName)
        {
            var builder = new ConfigurationBuilder()
                .AddJsonFile(slnPath + fileName, true, true)
                .AddJsonFile(projectPath + fileName, true, true);
            Configuration = builder.Build();
        }
    }
}
