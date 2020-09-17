using System;
using System.Collections.Generic;
using System.Text;
using Xunit.Abstractions;

namespace nscreg.Business.Test.Base
{
    public class BaseTest
    {
        protected readonly ITestOutputHelper _helper;
        public BaseTest(ITestOutputHelper helper)
        {
            _helper = helper;
        }
    }
}
