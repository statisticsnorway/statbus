using System.Linq;
using nscreg.Data.Entities;

// ReSharper disable once CheckNamespace
namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddLegalForms(NSCRegDbContext context)
        {
            context.LegalForms.Add(new LegalForm { Name = "Business partnerships and societies" });
            context.SaveChanges();
        }
    }
}
