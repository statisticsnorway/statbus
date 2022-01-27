using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;

namespace nscreg.Server.Common.Services.DataSources
{
    public class SaveManager
    {
        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>> _createByType;


        private readonly Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>> _updateByType;
        private readonly BulkUpsertUnitService _bulkUpsertUnitService;

        public  SaveManager(BulkUpsertUnitService bulkUpsertUnitService)
        {
            _bulkUpsertUnitService = bulkUpsertUnitService;

            _createByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, _) =>
                    _bulkUpsertUnitService.CreateLegalWithEnterpriseAndLocal(unit as LegalUnit),
                [StatUnitTypes.LocalUnit] = (unit, _) =>
                    _bulkUpsertUnitService.CreateLocalUnit(unit as LocalUnit),
                [StatUnitTypes.EnterpriseUnit] = (unit, _) =>
                   _bulkUpsertUnitService.CreateEnterpriseWithGroup(unit as EnterpriseUnit)
            };
            _updateByType = new Dictionary<StatUnitTypes, Func<StatisticalUnit, StatisticalUnit, Task>>
            {
                [StatUnitTypes.LegalUnit] = (unit, hunit) =>
                    _bulkUpsertUnitService.EditLegalUnit(unit as LegalUnit, hunit as LegalUnit ),
                [StatUnitTypes.LocalUnit] = (unit, hunit) =>
                    _bulkUpsertUnitService.EditLocalUnit(unit as LocalUnit, hunit as LocalUnit),
                [StatUnitTypes.EnterpriseUnit] = (unit, hunit) =>
                    _bulkUpsertUnitService.EditEnterpriseUnit(unit as EnterpriseUnit, hunit as EnterpriseUnit )
            };
        }

        private async Task<(string, bool)> SaveStatUnitsUpload(StatisticalUnit parsedUnit, DataSource dataSource, bool isNeW, StatisticalUnit historyUnit)
        {
            if (dataSource.Priority != DataSourcePriority.Trusted &&
                (dataSource.Priority != DataSourcePriority.Ok || isNeW))
                return (null, false);

            var saveAction =
                !isNeW && ( dataSource.AllowedOperations == DataSourceAllowedOperation.Alter
                || dataSource.AllowedOperations == DataSourceAllowedOperation.CreateAndAlter)
                ? _updateByType[dataSource.StatUnitType] : _createByType[dataSource.StatUnitType];

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
            if (System.Diagnostics.Debugger.IsAttached)
            {
                return ex + (ex.InnerException != null ? Environment.NewLine + GetFullExceptionMessage(ex.InnerException) : "");
            }
            return ex.Message + (ex.InnerException != null ? Environment.NewLine + GetFullExceptionMessage(ex.InnerException) : "");
        }

        public async Task<(string, bool)> SaveUnit(StatisticalUnit parsedUnit, DataSource dataSource, string userId, bool isNew, StatisticalUnit historyUnit)
        {
            return await SaveStatUnitsUpload(parsedUnit, dataSource, isNew, historyUnit);
        }

    }
}
