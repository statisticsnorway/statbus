using System;

namespace nscreg.Utilities
{
    public class StaisticalUnitNotFoundException : Exception
    {
        public StaisticalUnitNotFoundException()
        {
        }

        public StaisticalUnitNotFoundException(string message)
        : base(message)
        {
        }

        public StaisticalUnitNotFoundException(string message, Exception inner)
        : base(message, inner)
        {
        }
    }
}
