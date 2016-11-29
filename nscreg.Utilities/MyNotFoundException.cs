using System;

namespace nscreg.Utilities
{
    public class MyNotFoundException : Exception
    {
        public MyNotFoundException(string message)
        : base(message)
        {
        }

        public MyNotFoundException(string message, Exception inner)
        : base(message, inner)
        {
        }
    }
}
