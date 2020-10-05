using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Server.Common.Helpers;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Common.Services.DataSources
{
    public class SaveManager
    {
        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>> _createByType;

        private readonly ElasticBulkService _elasticService;

        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>> _updateByType; 

        private  SaveManager(NSCRegDbContext context, string userId, DataAccessPermissions permissions, ElasticBulkService service, UpsertUnitBulkBuffer buffer)
        {
            _elasticService = service;
            var creationHelper = new BulkUpsertUnitService(context, _elasticService, buffer);
            var editUnitService = new EditUnitService(context, userId, _elasticService, permissions);
            _createByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, _) =>
                    creationHelper.CreateLegalWithEnterpriseAndLocal(unit as LegalUnit),
                [StatUnitTypes.LocalUnit] = (unit, _) =>
                    creationHelper.CreateLocalUnit(unit as LocalUnit),
                [StatUnitTypes.EnterpriseUnit] = (unit, _) =>
                    creationHelper.CreateEnterpriseWithGroup(unit as EnterpriseUnit)
            };
            _updateByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, hunit) =>
                    editUnitService.EditLegalUnit(unit as LegalUnit, hunit as LegalUnit ),
                [StatUnitTypes.LocalUnit] = (unit, hunit) =>
                    editUnitService.EditLocalUnit(unit as LocalUnit, hunit as LocalUnit),
                [StatUnitTypes.EnterpriseUnit] = (unit, hunit) =>
                    editUnitService.EditEnterpriseUnit(unit as EnterpriseUnit, hunit as EnterpriseUnit )
            };
        }

        public static async Task<SaveManager> CreateSaveManager(NSCRegDbContext context, string userId, DataAccessPermissions permissions, ElasticBulkService service, UpsertUnitBulkBuffer buffer)
        {
            var saveManager = new SaveManager(context, userId, permissions, service, buffer);
            await saveManager._elasticService.CheckElasticSearchConnection();
            return saveManager;
        }

        private async Task<(string, bool)> SaveStatUnitsUpload(StatisticalUnit parsedUnit, DataSource dataSource, bool isNeW, StatisticalUnit historyUnit)
        {
            if (dataSource.Priority != DataSourcePriority.Trusted &&
                (dataSource.Priority != DataSourcePriority.Ok || isNeW))
                return (null, false);

            var saveAction =
                !isNeW && ( dataSource.AllowedOperations == DataSourceAllowedOperation.Alter || dataSource.AllowedOperations == DataSourceAllowedOperation.CreateAndAlter) ? _updateByType[dataSource.StatUnitType] : _createByType[dataSource.StatUnitType];

            try
            {
                await saveAction(parsedUnit, historyUnit);
            }
            catch (Exception ex)
            {
                return (GetFullExceptionMessage(ex), false);
            }
            return (null, true);
        }

        private string GetFullExceptionMessage(Exception ex)
        {
#if DEBUG
            return ex + (ex.InnerException != null ? Environment.NewLine + GetFullExceptionMessage(ex.InnerException) : "");
#else
            return ex.Message + (ex.InnerException != null ? Environment.NewLine + GetFullExceptionMessage(ex.InnerException) : "");
#endif
        }

        public async Task<(string, bool)> SaveUnit(StatisticalUnit parsedUnit, DataSource dataSource, string userId, bool isNew, StatisticalUnit historyUnit)
        {
            return await SaveStatUnitsUpload(parsedUnit, dataSource, isNew, historyUnit);
        }

    }
}
