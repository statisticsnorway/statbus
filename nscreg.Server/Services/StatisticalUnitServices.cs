using System.Linq;
using nscreg.Data;

namespace nscreg.Server.Services
{
    public class StatisticalUnitServices
    {
        public static string Delete(NSCRegDbContext context, int id)
        {
            var localStatUnit = context.LocalUnits.FirstOrDefault(x => x.RegId == id);
            var legalStatUnit = context.LegalUnits.FirstOrDefault(x => x.RegId == id);
            var entUStatUnit = context.EnterpriseUnits.FirstOrDefault(x => x.RegId == id);
            var entGStatUnit = context.EnterpriseGroups.FirstOrDefault(x => x.RegId == id);

            if (localStatUnit != null)
            {
                localStatUnit.IsDeleted = true;
                return "OK";
            }
            if (legalStatUnit != null)
            {
                legalStatUnit.IsDeleted = true;
                return "OK";
            }
            if (entUStatUnit != null)
            {
                entUStatUnit.IsDeleted = true;
                return "OK";
            }
            if (entGStatUnit != null)
            {
                entGStatUnit.IsDeleted = true;
                return "OK";
            }

            return "NotFound";
        }
    }
}
