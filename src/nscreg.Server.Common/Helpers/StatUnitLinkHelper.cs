using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using System.Linq;

namespace nscreg.Server.Common.Helpers
{
    public partial class StatUnitCreationHelper
    {
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

        private async Task LinkLocalToLegalAsync(IEnumerable<LocalUnit> sameStatIdLocalUnits, LegalUnit legalUnit)
        {
            foreach (var existingLocalUnit in sameStatIdLocalUnits)
            {
                existingLocalUnit.LegalUnitId = legalUnit.RegId;
                _dbContext.LocalUnits.Update(existingLocalUnit);
            }
            await _dbContext.SaveChangesAsync();

            var localsOfLegal = _dbContext.LocalUnits.Where(lou => lou.RegId == legalUnit.RegId)
                .Select(x => x.RegId).ToList();
            legalUnit.HistoryLocalUnitIds = string.Join(",", localsOfLegal);
            _dbContext.Update(legalUnit);

            await _dbContext.SaveChangesAsync();
        }
    }
}
