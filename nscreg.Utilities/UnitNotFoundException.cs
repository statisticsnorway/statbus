using System;

namespace nscreg.Utilities
{
    public class UnitNotFoundException : Exception
    {
        public UnitNotFoundException()
        {
        }

        public UnitNotFoundException(string message)
        : base(message)
        {
        }

        public UnitNotFoundException(string message, Exception inner)
        : base(message, inner)
        {
        }
    }
}
