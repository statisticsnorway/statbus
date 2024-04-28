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

        [Fact]
        private void GetVariablesMappingArray()
        {
            var obj = new DataSource {VariablesMapping = "NscCode-EntGroupId,Tin-EntGroupRole" };

            var actual = obj.VariablesMappingArray;

            Assert.Equal("NscCode", actual[0].source);
            Assert.Equal("EntGroupId", actual[0].target);
            Assert.Equal("Tin", actual[1].source);
            Assert.Equal("EntGroupRole", actual[1].target);
        }
    }
}
