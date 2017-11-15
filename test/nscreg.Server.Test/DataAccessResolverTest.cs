using System.Collections.Generic;
using nscreg.Utilities;
using Newtonsoft.Json;
using Xunit;

namespace nscreg.Server.Test
{
    public class DataAccessResolverTest
    {
        [Fact]
        void IgnoresSpecifiedPropertiesTest()
        {
            var obj = new { OkProp = 1, BadProp = 2, BadProp2 = 3 };
            var target = DataAccessResolver.Execute(obj, new HashSet<string>() { $"{obj.GetType().Name}.OkProp" });
            var serialized = JsonConvert.SerializeObject(target, Formatting.None);
            Assert.Equal("{\"okProp\":1}", serialized);
        }

        [Fact]
        void ContainsSubPropertiesTest()
        {
            var subObj = new { SubOne = 2.1, SubTwo = 2.2 };
            var obj = new { One = 1, Two = subObj, Three = 3 };
            const string expected = "{\"one\":1,\"two\":{\"subOne\":2.1,\"subTwo\":2.2},\"three\":3}";
            var target = DataAccessResolver.Execute(obj, new HashSet<string>() { $"{obj.GetType().Name}.One", $"{obj.GetType().Name}.Two", $"{obj.GetType().Name}.Three" });
            var serialized = JsonConvert.SerializeObject(target, Formatting.None);
            Assert.Equal(expected, serialized);
        }

        [Fact]
        void PostProcessingTest()
        {
            var obj = new { OkProp = 1, BadProp = 2, BadProp2 = 3 };
            var target = DataAccessResolver.Execute(obj, new HashSet<string>() { $"{obj.GetType().Name}.OkProp" }, jo =>
            {
                jo.Add("payload", "l33t");
            });
            var serialized = JsonConvert.SerializeObject(target, Formatting.None);
            Assert.Equal("{\"okProp\":1,\"payload\":\"l33t\"}", serialized);
        }

        [Fact]
        void CastObjectTest()
        {
            var obj = new { OkProp = 1 };
            var target = DataAccessResolver.Execute((object)obj, new HashSet<string>() { $"{obj.GetType().Name}.OkProp" });
            var serialized = JsonConvert.SerializeObject(target, Formatting.None);
            Assert.Equal("{\"okProp\":1}", serialized);
        }

        [Fact]
        void CastGegericTest()
        {
            var obj = new { OkProp = 1 };
            var target = DataAccessResolver.Execute<object>(obj, new HashSet<string>() { $"{obj.GetType().Name}.OkProp" });
            var serialized = JsonConvert.SerializeObject(target, Formatting.None);
            Assert.Equal("{\"okProp\":1}", serialized);
        }
    }
}
