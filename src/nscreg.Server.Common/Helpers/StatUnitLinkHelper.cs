using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using System.Linq;
using Microsoft.EntityFrameworkCore;

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
    }
}
