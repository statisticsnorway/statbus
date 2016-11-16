using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Server.Test
{
    public class RoleTest
    {
        [Fact]
        public void AccessToSystemFunctionsArrayGetTest()
        {
            Role role = new Role { AccessToSystemFunctions = "1,2,3" };
            var actual = role.AccessToSystemFunctionsArray;
            var expected = new[] { 1, 2, 3 };
            Assert.Equal(expected, actual);
        }

        [Fact]
        public void AccessToSystemFunctionsArraySetTest()
        {
            var role = new Role();
            role.AccessToSystemFunctionsArray = new[] { 1, 2, 3 };
            var actual = role.AccessToSystemFunctions;
            var expected = "1,2,3";
            Assert.Equal(expected, actual);
        }
    }
}
