using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Server.Test
{
    public class RoleTest
    {
        [Fact]
        private void AccessToSystemFunctionsArrayGetTest()
        {
            var role = new Role {AccessToSystemFunctions = "1,2,3"};

            var actual = role.AccessToSystemFunctionsArray;

            Assert.Equal(new[] {1, 2, 3}, actual);
        }

        [Fact]
        private void AccessToSystemFunctionsArraySetTest()
        {
            var role = new Role {AccessToSystemFunctionsArray = new[] {1, 2, 3}};

            var actual = role.AccessToSystemFunctions;

            Assert.Equal("1,2,3", actual);
        }
    }
}
