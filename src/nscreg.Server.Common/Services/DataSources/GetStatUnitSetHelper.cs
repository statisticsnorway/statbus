using System;
using System.Linq;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Services.DataSources
{
    public static class GetStatUnitSetHelper
    {
        public static IQueryable<StatisticalUnit> GetStatUnitSet(NSCRegDbContext context, StatUnitTypes type)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return context.LocalUnits
                        .Include(x => x.Address)
                        .ThenInclude(x => x.Region)
                        .Include(x => x.PersonsUnits)
                        .ThenInclude(x => x.Person)
                        .Include(x => x.ActivitiesUnits)
                        .ThenInclude(x => x.Activity)
                        .ThenInclude(x => x.ActivityCategory)
                        .Include(x => x.ForeignParticipationCountriesUnits)
                        .ThenInclude(x => x.Country)
                        .AsNoTracking();

                case StatUnitTypes.LegalUnit:
                    return context.LegalUnits
                        .Include(x => x.Address)
                        .ThenInclude(x => x.Region)
                        .Include(x => x.PersonsUnits)
                        .ThenInclude(x => x.Person)
                        .Include(x => x.ActivitiesUnits)
                        .ThenInclude(x => x.Activity)
                        .ThenInclude(x => x.ActivityCategory)
                        .Include(x => x.ForeignParticipationCountriesUnits)
                        .ThenInclude(x => x.Country)
                        .AsNoTracking();

                case StatUnitTypes.EnterpriseUnit:
                    return context.EnterpriseUnits
                        .Include(x => x.Address)
                        .ThenInclude(x => x.Region)
                        .Include(x => x.PersonsUnits)
                        .ThenInclude(x => x.Person)
                        .Include(x => x.ActivitiesUnits)
                        .ThenInclude(x => x.Activity)
                        .ThenInclude(x => x.ActivityCategory)
                        .Include(x => x.ForeignParticipationCountriesUnits)
                        .ThenInclude(x => x.Country)
                        .AsNoTracking();
                default:
                    throw new InvalidOperationException("Unit type is not supported");

            }
        }

        public static StatisticalUnit CreateByType(StatUnitTypes types)
        {
            switch (types)
            {
                case StatUnitTypes.LegalUnit:
                    return  new LegalUnit();
                case StatUnitTypes.EnterpriseUnit:
                    return new EnterpriseUnit();
                case StatUnitTypes.LocalUnit:
                    return  new LocalUnit();
                default:
                    throw new InvalidOperationException("Unit type is not supported");
            }
        }
    }
}
