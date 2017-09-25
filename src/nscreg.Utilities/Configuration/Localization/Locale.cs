namespace nscreg.Utilities.Configuration.Localization
{
    /// <summary>
    /// Класс описывающий локаль - ключ и наименование
    /// например: { Key: "en-GB", Text: "English" }
    /// </summary>
    public class Locale
    {
        public string Key { get; set; }
        public string Text { get; set; }
    }
}
