namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class ActivityAdapterModel
    {
        public ActivityAdapterModel(string mainActivity)
        {
            Name = mainActivity;
        }

        public string Name { get; set; }
        public string NameLanguage1 { get; set; }
        public string NameLanguage2 { get; set; }
    }
}
