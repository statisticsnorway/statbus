using System.Linq;
using nscreg.Data.Entities;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddSectorCodes(NSCRegDbContext context)
        {
            context.SectorCodes.Add(new SectorCode {Name = "A Нефинансовые корпорации"});
            context.SaveChanges();

            var nonFinCorp = context.SectorCodes
                .Where(x => x.Name == "A Нефинансовые корпорации")
                .Select(x => x.Id)
                .SingleOrDefault();
            context.SectorCodes.AddRange(
                new SectorCode
                {
                    Name = "государственные неинкорпорированные предприятия, принадлежащие центральному правительству",
                    Code = "1110",
                    ParentId = nonFinCorp
                },
                new SectorCode
                {
                    Name = "государственные акционерные предприятия, принадлежащие центральному правительству",
                    Code = "1120",
                    ParentId = nonFinCorp
                },
                new SectorCode
                {
                    Name = "государственные неинкорпорированные предприятия, принадлежащие местным органам власти",
                    Code = "1510",
                    ParentId = nonFinCorp
                },
                new SectorCode
                {
                    Name = "государственные акционерные предприятия, принадлежащие местным органам власти",
                    Code = "1520",
                    ParentId = nonFinCorp
                },
                new SectorCode
                {
                    Name = "частные нефинансовые объединенные предприятия",
                    Code = "2100",
                    ParentId = nonFinCorp
                },
                new SectorCode
                {
                    Name = "частные нефинансовые неинкорпорированные предприятия",
                    Code = "2300",
                    ParentId = nonFinCorp
                },
                new SectorCode
                {
                    Name = "частные некоммерческие организации, обслуживающие предприятия",
                    Code = "2500",
                    ParentId = nonFinCorp
                });

            context.SectorCodes.Add(new SectorCode {Name = "B Финансовые корпорации"});
            context.SaveChanges();

            var financeCorp = context.SectorCodes
                .Where(x => x.Name == "B Финансовые корпорации")
                .Select(x => x.Id)
                .SingleOrDefault();

            context.SectorCodes.AddRange(
                new SectorCode {Name = "Национальный банк", Code = "3100", ParentId = financeCorp},
                new SectorCode {Name = "банки", Code = "3200", ParentId = financeCorp},
                new SectorCode {Name = "ипотечные компании", Code = "3500", ParentId = financeCorp},
                new SectorCode {Name = "финансовые компании", Code = "3600", ParentId = financeCorp},
                new SectorCode {Name = "государственные кредитные организации", Code = "3900", ParentId = financeCorp},
                new SectorCode {Name = "финансовые холдинговые компании", Code = "4100", ParentId = financeCorp},
                new SectorCode {Name = "паевые инвестиционные фонды", Code = "4300", ParentId = financeCorp},
                new SectorCode
                {
                    Name = "инвестиционные трасты и фонды прямых инвестиций",
                    Code = "4500",
                    ParentId = financeCorp
                },
                new SectorCode
                {
                    Name = "прочие финансовые предприятия, кроме страховых компаний и пенсионных фондов",
                    Code = "4900",
                    ParentId = financeCorp
                },
                new SectorCode
                {
                    Name = "компании по страхованию жизни и пенсионные фонды",
                    Code = "5500",
                    ParentId = financeCorp
                },
                new SectorCode
                {
                    Name = "компании, не связанные со страхованием жизни",
                    Code = "5700",
                    ParentId = financeCorp
                });

            context.SectorCodes.Add(new SectorCode {Name = "C Общее правительство"});
            context.SaveChanges();

            var generalGov = context.SectorCodes
                .Where(x => x.Name == "C Общее правительство")
                .Select(x => x.Id)
                .SingleOrDefault();

            context.SectorCodes.AddRange(
                new SectorCode {Name = "центральное правительство", Code = "6100", ParentId = generalGov},
                new SectorCode {Name = "местное самоуправление", Code = "6500", ParentId = generalGov});

            context.SectorCodes.Add(new SectorCode
            {
                Name = "D Некоммерческие организации, обслуживающие домашние хозяйства"
            });
            context.SaveChanges();

            var xx = context.SectorCodes
                .Where(x => x.Name == "D Некоммерческие организации, обслуживающие домашние хозяйства")
                .Select(x => x.Id)
                .SingleOrDefault();

            context.SectorCodes.Add(new SectorCode
            {
                Name = "некоммерческие организации, обслуживающие домашние хозяйства",
                Code = "7000",
                ParentId = xx
            });

            context.SectorCodes.Add(new SectorCode {Name = "E Домохозяйства"});
            context.SaveChanges();

            var houseHolds = context.SectorCodes
                .Where(x => x.Name == "E Домохозяйства")
                .Select(x => x.Id).
                SingleOrDefault();

            context.SectorCodes.AddRange(
                new SectorCode
                {
                    Name = "некорпоративные предприятия в домохозяйствах",
                    Code = "8200",
                    ParentId = houseHolds
                },
                new SectorCode {Name = "жилищные кооперативы", Code = "8300", ParentId = houseHolds},
                new SectorCode
                {
                    Name = "сотрудники, получатели дохода от собственности, пенсий и социальных отчислений, студентов",
                    Code = "8500",
                    ParentId = houseHolds
                });

            context.SectorCodes.Add(new SectorCode {Name = "F Остальной мир"});
            context.SaveChanges();

            var restWorld = context.SectorCodes
                .Where(x => x.Name == "F Остальной мир")
                .Select(x => x.Id)
                .SingleOrDefault();

            context.SectorCodes.Add(new SectorCode {Name = "остальной мир", Code = "9000", ParentId = restWorld});
            context.SaveChanges();
        }
    }
}
