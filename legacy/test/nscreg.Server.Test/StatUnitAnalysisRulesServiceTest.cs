using Microsoft.Extensions.Configuration;
using nscreg.Data;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using System.IO;
using System.Linq;
using Xunit;

namespace nscreg.Server.Test
{
    public class StatUnitAnalysisRulesServiceTest
    {
        private readonly StatUnitAnalysisRules _analysisRules;
        private readonly DbMandatoryFields _mandatoryFields;
        private readonly ValidationSettings _validationSettings;
        // private readonly StatUnitTestHelper _helper;
        private readonly ConnectionSettings _connectionSettings;
        public StatUnitAnalysisRulesServiceTest()
        {
            var builder =
                new ConfigurationBuilder().AddJsonFile(
                    Path.Combine(
                        Directory.GetCurrentDirectory(),
                        "..", "..", "..", "..", "..",
                        "appsettings.Shared.json"),
                    true);
            var configuration = builder.Build();
            _analysisRules = configuration.GetSection(nameof(StatUnitAnalysisRules)).Get<StatUnitAnalysisRules>();
            _mandatoryFields = configuration.GetSection(nameof(DbMandatoryFields)).Get<DbMandatoryFields>();
            _validationSettings = configuration.GetSection(nameof(ValidationSettings)).Get<ValidationSettings>();
            //_helper = new StatUnitTestHelper(_analysisRules, _mandatoryFields, _validationSettings);
            _connectionSettings = configuration.GetSection(nameof(ConnectionSettings)).Get<ConnectionSettings>();

            //StartupConfiguration.ConfigureAutoMapper();
        }

        [Fact]
        public void CheckOrphanLocalUnits()
        {
            /* TODO Надо добавить тестовые данные и поправить реализовать всё в InMemory
            using (var context = DbContextHelper.Create(_connectionSettings))
            {
                var a = context.AnalysisQueues.ToList();
                var analysisQueue = context.AnalysisQueues.FirstOrDefault();
                if (analysisQueue != null)
                {
                    var analysisService = new AnalyzeService(context, _analysisRules, _mandatoryFields, _validationSettings);
                    analysisService.AnalyzeStatUnits(analysisQueue);
                }
            }
            */
        }
    }
}
