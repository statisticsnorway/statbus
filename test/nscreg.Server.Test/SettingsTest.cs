using nscreg.Utilities.Configuration;
using System;
using System.Linq;
using Xunit;

namespace nscreg.Server.Test
{
    public class SettingsTest
    {
        [Fact]
        public void IsEqualsISettingsNamespaces()
        {
            var type = typeof(ISettings);
            var types = AppDomain.CurrentDomain.GetAssemblies()
                .SelectMany(s => s.GetTypes())
                .Where(p => type.IsAssignableFrom(p));
            Assert.Equal(types.Select(x => x.Namespace).Count(), types.Where(w => w.Namespace == type.Namespace).Count());
        }
    }
}
