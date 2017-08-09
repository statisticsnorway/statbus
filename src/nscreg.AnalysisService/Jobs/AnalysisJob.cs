using System;
using System.Collections.Generic;
using System.Threading;
using nscreg.Business.Analysis.Enums;
using nscreg.Business.Analysis.StatUnit;
using nscreg.Data;
using nscreg.Services.Analysis.StatUnit;
using nscreg.ServicesUtils.Interfaces;

namespace nscreg.AnalysisService.Jobs
{
    internal class AnalysisJob : IJob
    {
        public int Interval { get; }
        private readonly IStatUnitAnalyzeService _analysisService;

        public AnalysisJob(NSCRegDbContext ctx, int dequeueInterval)
        {
            Interval = dequeueInterval;
            var analyzer = new StatUnitAnalyzer(
                new Dictionary<StatUnitMandatoryFieldsEnum, bool>
                {
                    { StatUnitMandatoryFieldsEnum.CheckAddress, true },
                    { StatUnitMandatoryFieldsEnum.CheckContactPerson, true },
                    { StatUnitMandatoryFieldsEnum.CheckDataSource, true },
                    { StatUnitMandatoryFieldsEnum.CheckLegalUnitOwner, true },
                    { StatUnitMandatoryFieldsEnum.CheckName, true },
                    { StatUnitMandatoryFieldsEnum.CheckRegistrationReason, true },
                    { StatUnitMandatoryFieldsEnum.CheckShortName, true },
                    { StatUnitMandatoryFieldsEnum.CheckStatus, true },
                    { StatUnitMandatoryFieldsEnum.CheckTelephoneNo, true },
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
            _analysisService = new StatUnitAnalyzeService(ctx, analyzer);
        }

        public async void Execute(CancellationToken cancellationToken)
        {
            _analysisService.AnalyzeStatUnits();
        }

        public async void OnException(Exception e)
        {
            throw new NotImplementedException();
        }
    }
}
