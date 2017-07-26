using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Services.Analysis.StatUnit;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class AnalyzeService
    {
        private readonly NSCRegDbContext _dbContext;

        public AnalyzeService(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task<SearchVm<InconsistentRecord>> GetInconsistentRecords(PaginationModel model)
        {
            var analyzer = new StatUnitAnalyzer(
                new Dictionary<StatUnitMandatoryFieldsEnum, bool>
                {
                    {StatUnitMandatoryFieldsEnum.CheckAddress, true},
                    {StatUnitMandatoryFieldsEnum.CheckContactPerson, true},
                    {StatUnitMandatoryFieldsEnum.CheckDataSource, true},
                    {StatUnitMandatoryFieldsEnum.CheckLegalUnitOwner, true},
                    {StatUnitMandatoryFieldsEnum.CheckName, true},
                    {StatUnitMandatoryFieldsEnum.CheckRegistrationReason, true},
                    {StatUnitMandatoryFieldsEnum.CheckShortName, true},
                    {StatUnitMandatoryFieldsEnum.CheckStatus, true},
                    {StatUnitMandatoryFieldsEnum.CheckTelephoneNo, true},
                },
                new Dictionary<StatUnitConnectionsEnum, bool>
                {
                    {StatUnitConnectionsEnum.CheckRelatedActivities, true},
                    {StatUnitConnectionsEnum.CheckRelatedLegalUnit, true},
                    {StatUnitConnectionsEnum.CheckAddress, true},
                },
                new Dictionary<StatUnitOrphanEnum, bool>
                {
                    {StatUnitOrphanEnum.CheckRelatedEnterpriseGroup, true},
                });

            IStatUnitAnalyzeService analysisService = new StatUnitAnalyzeService(_dbContext, analyzer);
            var statUnits =
                _dbContext.StatisticalUnits.Select(su => new Tuple<int, StatUnitTypes>(su.RegId, su.UnitType)).ToList();

            var analyzeResult = analysisService.AnalyzeStatUnits(statUnits);

            var records = analyzeResult.Select(x => new InconsistentRecord(x.Key, x.Value.Type, x.Value.Name, new List<string>())).ToList();
            var total = records.Count;
            var skip = model.PageSize * (model.Page - 1);
            var take = model.PageSize;

            var paginatedRecords = records.OrderBy(v => v.Type).ThenBy(n => n.Name)
                .Skip(take >= total ? 0 : skip > total ? skip % total : skip)
                .Take(take)
                .ToList();

            return SearchVm<InconsistentRecord>.Create(paginatedRecords, total);
        }
    }
}
