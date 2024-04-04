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
            var contractResolver = new DynamicContractResolver(obj.GetType(), new[] { "OkProp" });

            var serialized = JsonConvert.SerializeObject(obj, new JsonSerializerSettings { ContractResolver = contractResolver });

            Assert.Contains("okProp", serialized);
            Assert.DoesNotContain("badProp", serialized);
        }

        [Fact]
        void ContainsSubPropertiesTest()
        {
            var subObj = new {SubOne = 2.1, SubTwo = 2.2};
            var obj = new {One = 1, Two = subObj, Three = 3};
            const string expected = "{\"one\":1,\"two\":{\"subOne\":2.1,\"subTwo\":2.2},\"three\":3}";
            var contractResolver = new DynamicContractResolver(obj.GetType(), new []{"One", "Two", "Three"});
            var serialized = JsonConvert.SerializeObject(obj, new JsonSerializerSettings {ContractResolver = contractResolver} );
            Assert.Equal(expected,serialized);
        }
    }
}
