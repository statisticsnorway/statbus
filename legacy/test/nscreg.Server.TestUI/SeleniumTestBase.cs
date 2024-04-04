using System;
using OpenQA.Selenium.Remote;
using Xunit;

namespace nscreg.Server.TestUI
{
    [TestCaseOrderer("nscreg.Server.TestUI.Commons.PriorityOrderer", "nscreg.Server.TestUI")]
    public abstract class SeleniumTestBase : IDisposable
    {
        protected RemoteWebDriver Driver { get; }

        protected SeleniumTestBase()
        {
            Driver = Setup.CreateWebDriver();
        }

        public void Dispose()
        {
            Driver.Dispose();
        }
    }
}
