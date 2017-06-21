using System.Linq;
using nscreg.Data.Entities;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddLegalForms(NSCRegDbContext context)
        {
            context.LegalForms.Add(new LegalForm { Name = "Хозяйственные товарищества и общества" });
            context.SaveChanges();
            var ff = context.LegalForms.Where(x => x.Name == "Хозяйственные товарищества и общества").Select(x => x.Id).SingleOrDefault();
            context.LegalForms.AddRange(new LegalForm { Name = "Акционерное общество", ParentId = ff });

            context.SaveChanges();
        }
    }
}
