using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using System.Linq;

namespace nscreg.Server.Common.Helpers
{
    public partial class StatUnitCreationHelper
    {
        private async Task LinkLocalsToLegalAsync(IEnumerable<LocalUnit> sameStatIdLocalUnits, LegalUnit legalUnit)
        {
            foreach (var localUnit in sameStatIdLocalUnits)
            {
                localUnit.LegalUnitId = legalUnit.RegId;
                _dbContext.LocalUnits.Update(localUnit);
            }
            await _dbContext.SaveChangesAsync();

            var localsOfLegal = _dbContext.LocalUnits.Where(lou => lou.RegId == legalUnit.RegId)
                .Select(x => x.RegId).ToList();
            legalUnit.HistoryLocalUnitIds = string.Join(",", localsOfLegal);
            _dbContext.Update(legalUnit);

            await _dbContext.SaveChangesAsync();
        }

       private async Task LinkLegalsToEnterpriseAsync(IEnumerable<LegalUnit> sameStatIdLegalUnits, EnterpriseUnit enterpriseUnit)
        {
            foreach (var legalUnit in sameStatIdLegalUnits)
            {
                legalUnit.EnterpriseUnitRegId = enterpriseUnit.RegId;
                _dbContext.LegalUnits.Update(legalUnit);
            }
            await _dbContext.SaveChangesAsync();

            var legalsOfEnterprise = _dbContext.LegalUnits.Where(leu => leu.RegId == enterpriseUnit.RegId)
                .Select(x => x.RegId).ToList();
            enterpriseUnit.HistoryLegalUnitIds = string.Join(",", legalsOfEnterprise);
            _dbContext.Update(enterpriseUnit);

            await _dbContext.SaveChangesAsync();
        }

        private async Task LinkEnterpriseToLegalAsync(EnterpriseUnit sameStatIdEnterprise, LegalUnit legalUnit)
        {
            legalUnit.EnterpriseUnitRegId = sameStatIdEnterprise.RegId;
            _dbContext.LegalUnits.Update(legalUnit);
            await _dbContext.SaveChangesAsync();

            var legalsOfEnterprise = _dbContext.LegalUnits.Where(leu => leu.RegId == sameStatIdEnterprise.RegId)
                .Select(x => x.RegId).ToList();
            sameStatIdEnterprise.HistoryLegalUnitIds += string.Join(",", legalsOfEnterprise);
            _dbContext.EnterpriseUnits.Update(sameStatIdEnterprise);
            await _dbContext.SaveChangesAsync();
        }

        private async Task LinkEnterprisesToGroupAsync(IEnumerable<EnterpriseUnit> sameStatIdEnterpriseUnits, EnterpriseGroup enterpriseGroup)
        {
            foreach (var enterpriseUnit in sameStatIdEnterpriseUnits)
            {
                enterpriseUnit.EntGroupId = enterpriseGroup.RegId;
                _dbContext.EnterpriseUnits.Update(enterpriseUnit);
            }
            await _dbContext.SaveChangesAsync();

            var enterprisesOfGroup = _dbContext.EnterpriseUnits.Where(eu => eu.RegId == enterpriseGroup.RegId)
                .Select(x => x.RegId).ToList();
            enterpriseGroup.HistoryEnterpriseUnitIds = string.Join(",", enterprisesOfGroup);
            _dbContext.Update(enterpriseGroup);

            await _dbContext.SaveChangesAsync();
        }
    }
}
