using nscreg.Data;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;

namespace nscreg.Server.Test.Helpers
{
    internal static class ServiceFactories
    {
        public static DataSourcesQueueService CreateEmptyConfiguredDataSourceQueueService(NSCRegDbContext ctx)
        {
            var analysisRules = new StatUnitAnalysisRules();
            var dbMandatoryFields = new DbMandatoryFields();
            var createSvc = new CreateService(ctx, analysisRules, dbMandatoryFields);
            var editSvc = new EditService(ctx, analysisRules, dbMandatoryFields);
            var servicesConfig = new ServicesSettings();
            return new DataSourcesQueueService(ctx, createSvc, editSvc, servicesConfig, dbMandatoryFields);
        }
    }
}
