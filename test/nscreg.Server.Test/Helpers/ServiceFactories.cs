using AutoMapper;
using nscreg.Data;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Utilities.Configuration;
using nscreg.Utilities.Configuration.DBMandatoryFields;
using nscreg.Utilities.Configuration.StatUnitAnalysis;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Test.Helpers
{
    internal static class ServiceFactories
    {
        //public static DataSourcesQueueService CreateEmptyConfiguredDataSourceQueueService(NSCRegDbContext ctx, IMapper mapper)
        //{
        //    var analysisRules = new StatUnitAnalysisRules();
        //    var dbMandatoryFields = new DbMandatoryFields();
        //    var validationSettings = new ValidationSettings();
        //    //var createSvc = new CreateService(ctx, analysisRules, dbMandatoryFields, validationSettings, mapper, shouldAnalyze: true);
        //    //var editSvc = new EditService(ctx, analysisRules, dbMandatoryFields, validationSettings, mapper);
        //    //var servicesConfig = new ServicesSettings();
        //    return new DataSourcesQueueService();
        //}
    }
}
