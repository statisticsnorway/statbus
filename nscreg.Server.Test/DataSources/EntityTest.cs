using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Server.Test.DataSources
{
    public class EntityTest
    {
        [Fact]
        private void GetAttributesToCheckArray()
        {
            var obj = new DataSource {AttributesToCheck = "a,b"};

            Assert.Equal(new[] {"a", "b"}, obj.AttributesToCheckArray);
        }

        [Fact]
        private void SetAttributesToCheckArray()
        {
            var obj = new DataSource {AttributesToCheckArray = new[] {"a", "b"}};

            Assert.Equal("a,b", obj.AttributesToCheck);
        }
    }
}
