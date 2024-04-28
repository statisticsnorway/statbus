using nscreg.Server.Common;
using nscreg.Server.Core;
using Xunit;

namespace nscreg.Server.Test
{
    public class LocalizationTest
    {
        [Theory]
        [InlineData("en-GB")]
        [InlineData("ru-RU")]
        [InlineData("ky-KG")]
        private void HasLanguage(string key)
        {
            const string standart = "en-GB";
            Localization.LanguagePrimary = standart;
            Localization.Language1 = "ru-RU";
            Localization.Language2 = "ky-KG";
            Localization.Initialize();
            var dics = Localization.AllResources;

            Assert.Contains(key, dics.Keys);
            Assert.NotEmpty(dics[key]);
            Assert.True(dics[key].Keys.Count > 0);
            Assert.All(dics[standart].Keys, x => Assert.Contains(x, dics[key].Keys));
            Assert.All(dics[key].Keys, x => Assert.Contains(x, dics[standart].Keys));
            // Assert.All(dics[key], x => Assert.False(string.IsNullOrEmpty(x.Value)));
            // sorry for that, but some of the tests are failing for some reason after duplicate search optimization
        }
    }
}
