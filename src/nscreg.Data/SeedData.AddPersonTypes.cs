using nscreg.Data.Entities;

namespace nscreg.Data
{
    internal static partial class SeedData
    {
        public static void AddPersonTypes(NSCRegDbContext context)
        {
            context.PersonTypes.Add(new PersonType { Name = "Контактное лицо", IsDeleted = false, NameLanguage1 = "ContactPerson", NameLanguage2 = "Байланышуучу адам" });
            context.PersonTypes.Add(new PersonType { Name = "Учредитель", IsDeleted = false, NameLanguage1 = "Founder", NameLanguage2 = "Уюмдаштыруучу" });
            context.PersonTypes.Add(new PersonType { Name = "Владелец", IsDeleted = false, NameLanguage1 = "Owner", NameLanguage2 = "Ээси" });
            context.PersonTypes.Add(new PersonType { Name = "Руководитель", IsDeleted = false, NameLanguage1 = "Director", NameLanguage2 = "Башкарма" });
            context.SaveChanges();
        }
    }
}
