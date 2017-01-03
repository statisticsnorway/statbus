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
            var dics = Localization.AllResources;
            Assert.Contains(key, dics.Keys);
            Assert.NotEmpty(dics[key]);
            Assert.True(dics[key].Keys.Count > 0);
            Assert.All(dics[standart].Keys, x => Assert.Contains(x, dics[key].Keys));
            Assert.All(dics[key].Keys, x => Assert.Contains(x, dics[standart].Keys));
            Assert.All(dics[key], x => Assert.False(string.IsNullOrEmpty(x.Value)));
        }
    }
}
