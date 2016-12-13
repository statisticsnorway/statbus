using Newtonsoft.Json;
using nscreg.Utilities;
using Xunit;

namespace nscreg.Server.Test
{
    public class DynamicContractResolverTest
    {
        [Fact]
        void IgnoresSpecifiedPropertiesTest()
        {
            var obj = new { OkProp = 1, BadProp = 2, BadProp2 = 3 };
            var contractResolver = new DynamicContractResolver(new[] { "OkProp" });

            var serialized = JsonConvert.SerializeObject(obj, new JsonSerializerSettings { ContractResolver = contractResolver });

            Assert.Contains("okProp", serialized);
            Assert.DoesNotContain("badProp", serialized);
        }
    }
}
