using nscreg.Data;
using nscreg.TestUtils;
using System;
using Xunit.Abstractions;

namespace nscreg.Business.Test.Base
{
    public abstract class BaseTest: IDisposable
    {
        protected readonly ITestOutputHelper _helper;
        protected BaseTest(ITestOutputHelper helper)
        {
            _helper = helper;
            DatabaseContext = InMemoryDb.CreateDbContext();
        }

        public virtual void Dispose() => DatabaseContext?.Dispose();

        protected NSCRegDbContext DatabaseContext { get; }
    }
}
