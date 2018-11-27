namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class ActivityAdapterModel
    {
        public ActivityAdapterModel(string mainActivity, string mainActivityLanguage1, string mainActivityLanguage2)
        {
            Name = mainActivity;
            NameLanguage1 = mainActivityLanguage1;
            NameLanguage2 = mainActivityLanguage2;
        }

        public string Name { get; set; }
        public string NameLanguage1 { get; set; }
        public string NameLanguage2 { get; set; }
    }
}
